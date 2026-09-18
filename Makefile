FIXTURE ?= minimal
ROOT := $(CURDIR)/tmp
ANSIBLE_ARGS := tests/main.yaml --inventory localhost, --extra-vars fixture=$(FIXTURE)

.PHONY: lint check test validate clean

lint:
	ansible-lint

check-%:
	$(MAKE) --no-print-directory check FIXTURE="$*"
check:
	rm -rf "$(ROOT)"
	ansible-playbook $(ANSIBLE_ARGS) --check

test-%:
	$(MAKE) --no-print-directory test FIXTURE="$*"
test:
	rm -rf "$(ROOT)"
	ansible-playbook $(ANSIBLE_ARGS)

validate-%:
	$(MAKE) --no-print-directory validate FIXTURE="$*"
validate:
	docker compose --project-directory "$(ROOT)" config -q
	docker compose --project-directory "$(ROOT)" run --rm authelia \
		authelia config validate --config /config/configuration.yml

clean:
	rm -rf "$(ROOT)"
