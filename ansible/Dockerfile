# Ansible runner image — used both locally (make deploy) and by GitLab CI.
FROM python:3.12-alpine

# ansible-core is pinned to a minor series, so a rebuild only picks up patch
# releases. The hosts run Debian 13, whose Python is 3.13 — beyond what 2.17
# (end-of-life) could manage, which stopped at 3.12. 2.21 needs Python >= 3.12
# on this side, which the base image provides.
RUN apk add --no-cache openssh-client bash curl \
 && pip install --no-cache-dir "ansible-core==2.21.*" awscli

# Bake collections into the image so runs are fast and reproducible
COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml \
      -p /usr/share/ansible/collections
ENV ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections

WORKDIR /work
