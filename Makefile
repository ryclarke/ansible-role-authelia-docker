FIXTURE ?= minimal
ROOT := $(CURDIR)/tmp
ANSIBLE_ARGS := tests/main.yaml --inventory localhost, --extra-vars fixture=$(FIXTURE)

# Detect the container runtime to use for live output validation. Prefers podman over docker if both are installed.
ifneq ($(shell command -v podman 2>/dev/null),)
export PODMAN_COMPOSE_WARNING_LOGS := false
CNT_BIN := podman
else ifneq ($(shell command -v docker 2>/dev/null),)
CNT_BIN := docker
else
CNT_BIN := echo "ERROR: you must install either podman or docker to run validations"; exit 1;
endif

.PHONY: lint
lint:
	@ansible-lint

.PHONY: check
check-%:
	@$(MAKE) --no-print-directory check FIXTURE="$*"
check: clean
	@ansible-playbook $(ANSIBLE_ARGS) --check

.PHONY: test
test-%:
	@$(MAKE) --no-print-directory test FIXTURE="$*"
test: clean
	@ansible-playbook $(ANSIBLE_ARGS)

.PHONY: validate
validate-%:
	@$(MAKE) --no-print-directory validate FIXTURE="$*"
validate:
	@echo "Validating compose resource definitions..."
	@${CNT_BIN} compose --project-directory "$(ROOT)" config -q

	@echo "Validating authelia configuration..."
	@${CNT_BIN} compose --project-directory "$(ROOT)" run -v $(ROOT)/secrets:/run/secrets:z,ro --rm authelia \
		authelia config validate --config /config/configuration.yml

.PHONY: clean
clean:
	@rm -rf "$(ROOT)"
