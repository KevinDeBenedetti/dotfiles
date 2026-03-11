.DEFAULT_GOAL := help
SHELL         := /bin/bash

DOCKER_FILE    := tests/docker/Dockerfile.test
DOCKER_COMPOSE := tests/docker/docker-compose.test.yml
TESTS_DIR      := tests

VM_NAME 			:= dotfiles-vm
# ──────────────────────────────────────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ──────────────────────────────────────────────────────────────────────────────
# Tests
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: test test-configs test-functions test-init test-security

test: ## Run all Bats tests
	bats $(TESTS_DIR)/

test-configs: ## Run config/file existence tests
	bats $(TESTS_DIR)/configs.bats

test-functions: ## Run shell function tests
	bats $(TESTS_DIR)/functions.bats

test-init: ## Run init.sh flag parsing tests
	bats $(TESTS_DIR)/init.bats

test-security: ## Run security profile tests
	bats $(TESTS_DIR)/security.bats

# ──────────────────────────────────────────────────────────────────────────────
# Lint & Validate
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: lint validate

lint: ## Run ShellCheck on all shell scripts
	find . -type f -name "*.sh" -not -path "*/test_helper/*" \
		-exec shellcheck --severity=warning --shell=bash --format=gcc {} +

validate: ## Validate YAML files with yamllint
	yamllint --strict .github/workflows/

# ──────────────────────────────────────────────────────────────────────────────
# Docker
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: docker-build docker-test-bats docker-test-init docker-test-dotfiles docker-test-security docker-test-full

docker-build: ## Build all Docker test stages
	docker-compose -f $(DOCKER_COMPOSE) build

docker-test-bats: ## Run Bats tests inside a Debian container
	docker build -f $(DOCKER_FILE) --target test-bats -t dotfiles-test-bats .

docker-test-init: ## Validate init.sh flag parsing in Docker
	docker build -f $(DOCKER_FILE) --target test-init -t dotfiles-test-init .

docker-test-dotfiles: ## Run dotfile-only install and verify symlinks in Docker
	docker build -f $(DOCKER_FILE) --target test-dotfiles -t dotfiles-test-dotfiles .

docker-test-security: ## Run security profile and verify configs in Docker
	docker build -f $(DOCKER_FILE) --target test-security -t dotfiles-test-security .

docker-test-full: ## Run full integration test (all profiles) in Docker
	docker build -f $(DOCKER_FILE) --target test-full -t dotfiles-test-full .

# ──────────────────────────────────────────────────────────────────────────────
# Git
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: submodules

submodules: ## Init and update git submodules (bats helpers)
	git submodule update --init --recursive

# ──────────────────────────────────────────────────────────────────────────────
# CI
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: ci

ci: lint validate test ## Run full CI pipeline locally (shellcheck + yamllint + bats)

# ──────────────────────────────────────────────────────────────────────────────
# VM
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: vm-create vm-install vm-shell vm-test vm-status vm-stop vm-start vm-clean vm-full vm-reset

vm-create: ## Create an Ubuntu 24.04 VM with Multipass (Debian-compatible)
	@echo "$(YELLOW)→ Creating VM '$(VM_NAME)'...$(RESET)"
	@multipass info $(VM_NAME) > /dev/null 2>&1 \
		&& echo "  ⚠️  VM already exists — run 'make vm-clean' first" \
		|| multipass launch 24.04 \
			--name $(VM_NAME) \
			--cpus 2 \
			--memory 2G \
			--disk 10G
	@echo "$(GREEN)✅ VM '$(VM_NAME)' ready$(RESET)"
	@multipass info $(VM_NAME)

vm-install: ## Run remote dotfiles install script inside the VM
	@echo "$(YELLOW)→ Running remote dotfiles install script...$(RESET)"
	@multipass exec $(VM_NAME) -- bash -c \
		"bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/debian/init.sh) -a"
	@echo "$(GREEN)✅ Install complete$(RESET)"

vm-shell: ## Open an interactive shell in the VM
	@echo "$(CYAN)→ Connecting to VM '$(VM_NAME)'...$(RESET)"
	@multipass shell $(VM_NAME)

vm-test: ## Verify the setup inside the VM
	@echo "$(YELLOW)→ Running verification checks...$(RESET)"
	@multipass exec $(VM_NAME) -- bash -c '\
		echo "" ;\
		echo "=== 📦 Packages ===" ;\
		for cmd in zsh git vim curl wget; do \
			command -v $$cmd > /dev/null 2>&1 \
				&& echo "  ✅ $$cmd: $$(command -v $$cmd)" \
				|| echo "  ❌ MISSING: $$cmd" ;\
		done ;\
		echo "" ;\
		echo "=== 🔒 SSH Config ===" ;\
		grep -q "PermitRootLogin no" /etc/ssh/sshd_config \
			&& echo "  ✅ PermitRootLogin no" \
			|| echo "  ⚠️  PermitRootLogin not hardened" ;\
		grep -q "PasswordAuthentication no" /etc/ssh/sshd_config \
			&& echo "  ✅ PasswordAuthentication no" \
			|| echo "  ⚠️  PasswordAuthentication not disabled" ;\
		echo "" ;\
		echo "=== 🔥 UFW ===" ;\
		sudo ufw status | grep -q "Status: active" \
			&& echo "  ✅ UFW active" \
			|| echo "  ⚠️  UFW not active" ;\
		echo "" ;\
		echo "=== ☸️  Kernel modules ===" ;\
		lsmod | grep -q "^overlay" \
			&& echo "  ✅ overlay loaded" \
			|| echo "  ⚠️  overlay not loaded" ;\
		lsmod | grep -q "^br_netfilter" \
			&& echo "  ✅ br_netfilter loaded" \
			|| echo "  ⚠️  br_netfilter not loaded" ;\
		echo "" ;\
		echo "=== 🖥️  System ===" ;\
		echo "  OS:     $$(grep PRETTY_NAME /etc/os-release | cut -d= -f2)" ;\
		echo "  Kernel: $$(uname -r)" ;\
		echo "  RAM:    $$(free -h | grep Mem | awk '"'"'{print $$2}'"'"')" ;\
		echo "  Disk:   $$(df -h / | tail -1 | awk '"'"'{print $$4}'"'"') free" ;\
	'
	@echo ""
	@echo "$(GREEN)✅ Verification done$(RESET)"

vm-status: ## Show VM status and info
	@multipass info $(VM_NAME) 2>/dev/null \
		|| echo "$(RED)❌ VM '$(VM_NAME)' not found — run 'make vm-create'$(RESET)"

vm-stop: ## Stop the VM (without deleting it)
	@echo "$(YELLOW)→ Stopping VM...$(RESET)"
	@multipass stop $(VM_NAME)
	@echo "$(GREEN)✅ VM stopped$(RESET)"

vm-start: ## Start a stopped VM
	@echo "$(YELLOW)→ Starting VM...$(RESET)"
	@multipass start $(VM_NAME)
	@echo "$(GREEN)✅ VM started$(RESET)"

vm-clean: ## Delete the VM and free disk space
	@echo "$(RED)→ Deleting VM '$(VM_NAME)'...$(RESET)"
	@multipass delete $(VM_NAME) --purge 2>/dev/null || true
	@echo "$(GREEN)✅ VM deleted$(RESET)"

vm-full: vm-create vm-install vm-test ## Full cycle: create VM + install + verify
	@echo ""
	@echo "$(GREEN)🎉 Full test cycle complete$(RESET)"
	@echo "  → make vm-shell   to connect"
	@echo "  → make vm-clean   to clean up"

vm-reset: vm-clean vm-create vm-install vm-test

