# Local runs via Docker — no Ansible install needed.
#   make build                      # build the runner image (once, or after requirements.yml changes)
#   make deploy                     # full run
#   make deploy TAGS=caching        # one step
#   make check                      # dry run (--check --diff)
#   KEY=~/.ssh/my-key.pem make deploy

IMAGE ?= wp-ansible-runner
KEY   ?= $(HOME)/.ssh/your-key.pem
TAGS  ?=

DOCKER_RUN = docker run --rm -it \
	-v $(CURDIR):/work -w /work \
	-v $(KEY):/root/.ssh/key.pem:ro \
	-e ANSIBLE_HOST_KEY_CHECKING=False \
	$(IMAGE)

PLAYBOOK_ARGS = site.yml --ask-vault-pass \
	-e ansible_ssh_private_key_file=/root/.ssh/key.pem \
	$(if $(TAGS),--tags $(TAGS),)

.PHONY: build deploy check lint

build:
	docker build -t $(IMAGE) .

deploy:
	$(DOCKER_RUN) ansible-playbook $(PLAYBOOK_ARGS)

check:
	$(DOCKER_RUN) ansible-playbook $(PLAYBOOK_ARGS) --check --diff

lint:
	$(DOCKER_RUN) ansible-playbook site.yml --syntax-check
