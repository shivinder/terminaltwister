#!/usr/bin/env bash
#
# Preflight checks before `terraform apply` in infra/envs/<env>.
#
#   ./infra/scripts/preflight.sh [test|production]     (default: test)
#
# Expectations are DERIVED from the Terraform config (required_version,
# aws_region, key_name, backup bucket) rather than hardcoded, so this script
# cannot drift from what the configs actually declare.
#
# Exit status: 0 = ready to apply, 1 = at least one blocking failure.
# Warnings never fail the run.

set -euo pipefail

ENVIRONMENT="${1:-test}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
ENV_DIR="$INFRA_DIR/envs/$ENVIRONMENT"

# --- output helpers ---

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_FAIL=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_FAIL=""; C_DIM=""; C_OFF=""
fi

fails=0
warns=0

ok()   { printf '  %s[ OK ]%s %s\n' "$C_OK" "$C_OFF" "$1"; }
warn() { printf '  %s[WARN]%s %s\n' "$C_WARN" "$C_OFF" "$1"; warns=$((warns + 1)); }
fail() { printf '  %s[FAIL]%s %s\n' "$C_FAIL" "$C_OFF" "$1"; fails=$((fails + 1)); }
note() { printf '         %s%s%s\n' "$C_DIM" "$1" "$C_OFF"; }

# True when $1 >= $2, comparing dotted versions numerically (1.9 < 1.15).
version_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]
}

# 0 = exists and we can reach it, 1 = does not exist, 2 = exists but owned
# by another account, 3 = could not determine.
bucket_status() {
  local out
  if out=$(aws s3api head-bucket --bucket "$1" --region "$REGION" 2>&1); then return 0; fi
  case "$out" in
    *404*|*"Not Found"*) return 1 ;;
    *403*|*Forbidden*)   return 2 ;;
    *)                   return 3 ;;
  esac
}

# --- resolve what the config expects ---

if [[ ! -d "$ENV_DIR" ]]; then
  printf '%s[FAIL]%s No such environment: %s\n' "$C_FAIL" "$C_OFF" "$ENV_DIR" >&2
  printf 'Usage: %s [test|production]\n' "$0" >&2
  exit 1
fi

extract() { sed -nE "$2" "$1" 2>/dev/null | head -1; }

REQ_TF=$(extract "$ENV_DIR/providers.tf" 's/.*required_version.*">=[[:space:]]*([0-9.]+)".*/\1/p')
REGION=$(extract "$ENV_DIR/variables.tf" 's/.*default[[:space:]]*=[[:space:]]*"(ap-[a-z0-9-]+)".*/\1/p')
KEY_NAME=$(grep -A5 'variable "key_name"' "$ENV_DIR/variables.tf" 2>/dev/null \
  | sed -nE 's/.*default[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' | head -1)
BACKUP_BUCKET=$(extract "$ENV_DIR/main.tf" 's/.*backup_bucket_name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p')
STATE_BUCKET=$(extract "$ENV_DIR/providers.tf" 's/.*bucket[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p')

# main.tf passes alarm_email straight through from the env's own variable, so the
# effective value is that variable's default unless TF_VAR_alarm_email overrides.
# The || true matters: grep exits 1 on no match and pipefail would kill the run.
ALARM_EMAIL=$(grep -A6 'variable "alarm_email"' "$ENV_DIR/variables.tf" 2>/dev/null \
  | sed -nE 's/.*default[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' | head -1 || true)

# Anchored, unlike the value extractions above: this one is a literal in main.tf
# and an unanchored match would also find it inside the comments that explain it.
SNAPSHOT_DAYS=$(extract "$ENV_DIR/main.tf" 's/^[[:space:]]*snapshot_retention_days[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p')

# TF_VAR_* overrides the config default, same as they would for Terraform.
KEY_NAME="${TF_VAR_key_name:-$KEY_NAME}"
ALARM_EMAIL="${TF_VAR_alarm_email:-$ALARM_EMAIL}"
SNAPSHOT_DAYS="${TF_VAR_snapshot_retention_days:-${SNAPSHOT_DAYS:-0}}"

: "${REQ_TF:=1.15}"
: "${REGION:=ap-southeast-2}"

printf '\nPreflight — environment %s%s%s (%s)\n\n' "$C_OK" "$ENVIRONMENT" "$C_OFF" "$REGION"

# --- 1. tooling ---

printf 'Tooling\n'

if command -v terraform >/dev/null 2>&1; then
  tf_ver=$(terraform version | head -1 | sed -E 's/^Terraform v//')
  if version_ge "$tf_ver" "$REQ_TF"; then
    ok "terraform $tf_ver (config requires >= $REQ_TF)"
  else
    fail "terraform $tf_ver is older than the required >= $REQ_TF"
    note "terraform init will refuse to run. Upgrade: https://developer.hashicorp.com/terraform/install"
  fi
else
  fail "terraform not found on PATH"
fi

if command -v aws >/dev/null 2>&1; then
  ok "aws cli $(aws --version 2>&1 | sed -E 's|^aws-cli/([^ ]+).*|\1|')"
else
  fail "aws cli not found on PATH — the remaining checks need it"
  printf '\n%d check(s) failed.\n' "$fails"
  exit 1
fi

# --- 2. credentials and region ---

printf '\nAWS access\n'

if ident=$(aws sts get-caller-identity --output text --query '[Account,Arn]' 2>&1); then
  ok "credentials valid — account $(cut -f1 <<<"$ident")"
  note "$(cut -f2 <<<"$ident")"
else
  fail "no usable AWS credentials"
  note "$ident"
fi

shell_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}"
if [[ "$shell_region" == "$REGION" ]]; then
  ok "shell region is $REGION"
elif [[ -z "$shell_region" ]]; then
  warn "no default region set in your shell (Terraform still uses $REGION from var.aws_region)"
  note "manual 'aws' commands will need --region $REGION"
else
  warn "shell region is $shell_region, config targets $REGION"
  note "Terraform is unaffected, but manual 'aws' commands will hit $shell_region"
fi

# --- 3. prerequisites the apply depends on ---

printf '\nPrerequisites\n'

if [[ -n "$KEY_NAME" ]]; then
  if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" >/dev/null 2>&1; then
    ok "EC2 key pair '$KEY_NAME' exists"
  else
    fail "EC2 key pair '$KEY_NAME' not found in $REGION"
    note "aws ec2 create-key-pair --key-name $KEY_NAME --region $REGION \\"
    note "  --query KeyMaterial --output text > ~/.ssh/$KEY_NAME.pem && chmod 600 ~/.ssh/$KEY_NAME.pem"
  fi
else
  warn "could not determine key_name from $ENV_DIR/variables.tf"
fi

if [[ -n "$STATE_BUCKET" ]]; then
  set +e; bucket_status "$STATE_BUCKET"; rc=$?; set -e
  case $rc in
    0) ok "state bucket '$STATE_BUCKET' exists" ;;
    1) fail "state bucket '$STATE_BUCKET' does not exist — bootstrap it first"
       note "cd $INFRA_DIR/initial-tasks && terraform init && terraform apply" ;;
    2) fail "state bucket '$STATE_BUCKET' exists but belongs to another account"
       note "S3 names are globally unique; choose a different name" ;;
    *) warn "could not determine the state of bucket '$STATE_BUCKET'" ;;
  esac
fi

if [[ -n "$BACKUP_BUCKET" ]]; then
  set +e; bucket_status "$BACKUP_BUCKET"; rc=$?; set -e
  case $rc in
    0) ok "backup bucket '$BACKUP_BUCKET' already exists (apply will adopt or no-op)" ;;
    1) ok "backup bucket name '$BACKUP_BUCKET' is free" ;;
    2) fail "backup bucket '$BACKUP_BUCKET' is taken by another account"
       note "rename it in $ENV_DIR/main.tf AND backup_s3_bucket_name in ansible/group_vars/$ENVIRONMENT.yml" ;;
    *) warn "could not determine the state of bucket '$BACKUP_BUCKET'" ;;
  esac
fi

# --- 4. config hygiene ---

printf '\nConfiguration\n'

if terraform -chdir="$INFRA_DIR" fmt -check -recursive >/dev/null 2>&1; then
  ok "terraform fmt is clean (CI enforces this)"
else
  warn "terraform fmt would reformat some files — CI's tf-validate job will fail"
  note "fix with: terraform fmt -recursive $INFRA_DIR"
fi

# Anchored: envs/test/main.tf carries a commented-out allowed_web_cidrs in the
# same style, and an unanchored match would report a commented-out
# admin_ssh_cidrs as set while the security group opens no SSH at all.
if grep -Eq '^[[:space:]]*admin_ssh_cidrs' "$ENV_DIR/main.tf" 2>/dev/null; then
  ok "admin_ssh_cidrs is set — SSH will be reachable from those CIDRs"
else
  warn "admin_ssh_cidrs not set: the security group will open NO SSH port"
  note "fine for CI deploys (the job allowlists its own IP); set it to run Ansible locally"
fi

# Both of these create nothing at their defaults, and "nothing" is indis-
# tinguishable from "working" until the night it matters — the same reason the
# module surfaces them as outputs. Say it before the apply, not after.

if [[ -n "$ALARM_EMAIL" ]]; then
  ok "backup-failure alerts go to $ALARM_EMAIL"
  note "AWS emails a confirmation link; until it is clicked, nothing is delivered"
else
  warn "alarm_email is empty: a failed — or missing — backup will alert nobody"
  note "set TF_VAR_alarm_email, or accept it for an environment you can rebuild"
fi

if [[ "$SNAPSHOT_DAYS" -gt 0 ]]; then
  ok "root-volume snapshots retained $SNAPSHOT_DAYS day(s)"
else
  warn "snapshot_retention_days is 0: no EBS snapshots of the root volume"
  note "expected for test; on production a lost disk means a full rebuild"
fi

# --- summary ---

printf '\n'
if (( fails > 0 )); then
  printf '%s%d blocking failure(s)%s, %d warning(s). Resolve the failures before applying.\n' \
    "$C_FAIL" "$fails" "$C_OFF" "$warns"
  exit 1
fi

printf '%sReady to apply%s (%d warning(s)).\n' "$C_OK" "$C_OFF" "$warns"
printf '  cd %s && terraform init && terraform plan\n\n' "$ENV_DIR"
