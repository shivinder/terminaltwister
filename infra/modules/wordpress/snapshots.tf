# --- Root volume snapshots ---
#
# The nightly S3 backup (ansible/roles/ops/templates/wp-backup.sh.j2) covers the
# database, wp-content, and — since the same change that added this file — the
# salts and TLS certs. What it does not cover is the machine: a lost root volume
# still means terraform apply, a full Ansible run, then wp-restore.sh.
#
# A daily EBS snapshot turns that into a volume swap. The two are complementary,
# not redundant: S3 gives 90 days of depth on the content, snapshots give a
# bootable disk for the last week.
#
# All of this is skipped when snapshot_retention_days is 0 (the default), so
# test — which is meant to be thrown away — creates nothing and costs nothing.

locals {
  snapshots_enabled = var.snapshot_retention_days > 0 ? 1 : 0
}

data "aws_iam_policy_document" "assume_dlm" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  count              = local.snapshots_enabled
  name               = "${local.name}-dlm"
  assume_role_policy = data.aws_iam_policy_document.assume_dlm.json
  tags               = local.common_tags
}

# AWS's managed policy rather than a hand-rolled one. It grants exactly what a
# snapshot lifecycle needs — CreateSnapshot, DeleteSnapshot, CreateTags on
# snapshots, and the EventBridge rules DLM manages on its own behalf — and AWS
# revises it as DLM gains features, which a copied inline policy would not track.
resource "aws_iam_role_policy_attachment" "dlm" {
  count      = local.snapshots_enabled
  role       = aws_iam_role.dlm[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "root_volume" {
  count              = local.snapshots_enabled
  description        = "Nightly snapshots of ${local.name} EBS volumes"
  execution_role_arn = aws_iam_role.dlm[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    # local.common_tags, not a literal "tt-wp-<env>-root". ec2.tf stamps exactly
    # these onto the root volume, so the target cannot drift out of step with
    # what is actually tagged — and a second volume added to this environment
    # later is picked up without anyone remembering to come back here.
    #
    # The same property cuts the other way after a restore: a detached volume
    # keeps its tags, so the disk you swapped out goes on being snapshotted
    # nightly until someone untags it. DLM offers no attachment-state filter to
    # fix that here, so the restore procedure in infra/README.md owns it — see
    # "Retire the old volume", and do not treat that step as optional.
    target_tags = local.common_tags

    schedule {
      name = "daily"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"

        # UTC, and so is the instance (timezone: UTC, set by base_hardening).
        # The backup cron runs at 03:00, so an hour later the snapshot catches a
        # disk that already holds that night's finished archives and is no
        # longer competing with mysqldump for I/O.
        times = ["04:00"]
      }

      # One snapshot a day, so a count of N is N days of history.
      retain_rule {
        count = var.snapshot_retention_days
      }

      # Carries Project/Environment/ManagedBy/Name from the volume onto each
      # snapshot, so cost allocation and console filtering work the same way
      # they do for everything else this module creates. Note ManagedBy comes
      # along too: the snapshots are made by DLM, not Terraform, and survive a
      # destroy — see "Tearing down" in infra/README.md.
      copy_tags = true

      tags_to_add = {
        SnapshotType = "dlm-daily"
      }
    }
  }

  tags = local.common_tags

  # Not a permissions race: CreateLifecyclePolicy validates the role's trust
  # relationship, not the policy attached to it, and the first snapshot is hours
  # away regardless. This is here so the two cannot succeed independently.
  #
  # Both resources reference the role, neither references the other, so Terraform
  # would otherwise create them in parallel — and if the attachment failed while
  # this succeeded, the apply would leave an ENABLED policy on a role that cannot
  # take a snapshot. The root_volume_snapshots output would then print a policy ID
  # and a retention window, reporting that snapshots are on when they are not,
  # which is the one thing that output exists to prevent. Ordering them means a
  # failed attachment leaves no policy, and the output correctly says DISABLED.
  depends_on = [aws_iam_role_policy_attachment.dlm]
}
