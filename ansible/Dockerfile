# Ansible runner image — used both locally (make deploy) and by GitLab CI.
FROM python:3.12-alpine

RUN apk add --no-cache openssh-client bash curl \
 && pip install --no-cache-dir "ansible-core==2.17.*" awscli

# Bake collections into the image so runs are fast and reproducible
COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml \
      -p /usr/share/ansible/collections
ENV ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections

WORKDIR /work
