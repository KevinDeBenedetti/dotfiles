.DEFAULT_GOAL := help
SHELL         := /bin/bash

DOCKER_FILE    := tests/docker/Dockerfile.test
DOCKER_COMPOSE := tests/docker/docker-compose.test.yml
TESTS_DIR      := tests

VM_NAME    := dotfiles-vm
VM_CONFIG  := tests/lima/debian-trixie.yaml
SSH_PORT   := $(or $(SSH_PORT),22)

# Terminal colors
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
CYAN   := \033[0;36m
RESET  := \033[0m
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

.PHONY: vm-create vm-install vm-shell vm-test vm-status vm-stop vm-start vm-clean vm-full vm-reset vm-lima-list

vm-create: ## Create a Debian 13 (trixie) VM with Lima
	@echo "$(YELLOW)→ Creating VM '$(VM_NAME)'...$(RESET)"
	@limactl list $(VM_NAME) > /dev/null 2>&1 \
		&& echo "  ⚠️  VM already exists — run 'make vm-clean' first" \
		|| limactl start \
			--name $(VM_NAME) \
			--cpus 2 \
			--memory 2 \
			--disk 10 \
			--tty=false \
			$(VM_CONFIG)
	@echo "$(GREEN)✅ VM '$(VM_NAME)' ready$(RESET)"
	@limactl list $(VM_NAME)

vm-install: ## Run local dotfiles install script inside the VM (via Lima mount)
	@echo "$(YELLOW)→ Running local dotfiles install script...$(RESET)"
	@limactl shell $(VM_NAME) bash -c "cd \"\$$HOME\" && bash $(CURDIR)/os/debian/init.sh -a"
	@echo "$(GREEN)✅ Install complete$(RESET)"

vm-shell: ## Open an interactive shell in the VM
	@echo "$(CYAN)→ Connecting to VM '$(VM_NAME)'...$(RESET)"
	@limactl shell $(VM_NAME)

vm-test: ## Verify the setup inside the VM
	@echo "$(YELLOW)→ Running verification checks...$(RESET)"
	@limactl shell $(VM_NAME) bash -c '\
		echo "" ;\
		echo "=== 📦 Packages ===" ;\
		for cmd in zsh git vim curl wget docker; do \
			command -v $$cmd > /dev/null 2>&1 \
				&& echo "  ✅ $$cmd: $$(command -v $$cmd)" \
				|| echo "  ❌ MISSING: $$cmd" ;\
		done ;\
		echo "" ;\
		echo "=== 🐳 Docker CE ===" ;\
		docker --version 2>/dev/null \
			&& echo "  ✅ Docker CE: $$(docker --version)" \
			|| echo "  ⚠️  Docker CE not installed" ;\
		dpkg -l docker-ce 2>/dev/null | grep -q "^ii" \
			&& echo "  ✅ docker-ce package installed" \
			|| echo "  ⚠️  docker-ce not found" ;\
		echo "" ;\
		echo "=== 🔒 SSH Config ===" ;\
		sudo grep -rq "PermitRootLogin no" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null \
			&& echo "  ✅ PermitRootLogin no" \
			|| echo "  ⚠️  PermitRootLogin not hardened" ;\
		sudo grep -rq "PasswordAuthentication no" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null \
			&& echo "  ✅ PasswordAuthentication no" \
			|| echo "  ⚠️  PasswordAuthentication not disabled" ;\
		echo "" ;\
		echo "=== 🔥 UFW ===" ;\
		sudo ufw status | grep -q "Status: active" \
			&& echo "  ✅ UFW active" \
			|| echo "  ⚠️  UFW not active" ;\
		echo "" ;\
		echo "=== 🛡️  AppArmor ===" ;\
		sudo systemctl is-active apparmor 2>/dev/null | grep -q "^active" \
			&& echo "  ✅ AppArmor active" \
			|| echo "  ⚠️  AppArmor not active" ;\
		command -v aa-status > /dev/null 2>&1 \
			&& sudo aa-status --verbose 2>/dev/null | head -4 \
			|| echo "  ⚠️  aa-status not available" ;\
		echo "" ;\
		echo "=== ⚙️  Sysctl Hardening ===" ;\
		for param in \
			"kernel.kptr_restrict=2" \
			"kernel.dmesg_restrict=1" \
			"kernel.randomize_va_space=2" \
			"kernel.yama.ptrace_scope=1" \
			"net.ipv4.tcp_syncookies=1" \
			"fs.protected_symlinks=1" \
			"fs.protected_hardlinks=1"; do \
			key="$$(echo $$param | cut -d= -f1)" ;\
			expected="$$(echo $$param | cut -d= -f2)" ;\
			actual="$$(sysctl -n $$key 2>/dev/null)" ;\
			[ "$$actual" = "$$expected" ] \
				&& echo "  ✅ $$key = $$actual" \
				|| echo "  ⚠️  $$key = $$actual (expected: $$expected)" ;\
		done ;\
		echo "" ;\
		echo "=== 📁 Filesystem ===";\
		grep -q "^tmpfs /tmp" /etc/fstab 2>/dev/null \
			&& echo "  ✅ /tmp noexec entry in fstab" \
			|| echo "  ⚠️  /tmp not secured in fstab" ;\
		grep -q "/run/shm" /etc/fstab 2>/dev/null \
			&& echo "  ✅ /run/shm noexec entry in fstab" \
			|| echo "  ⚠️  /run/shm not secured in fstab" ;\
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
	@limactl list $(VM_NAME) 2>/dev/null \
		|| echo "$(RED)❌ VM '$(VM_NAME)' not found — run 'make vm-create'$(RESET)"

vm-stop: ## Stop the VM (without deleting it)
	@echo "$(YELLOW)→ Stopping VM...$(RESET)"
	@limactl stop $(VM_NAME)
	@echo "$(GREEN)✅ VM stopped$(RESET)"

vm-start: ## Start a stopped VM
	@echo "$(YELLOW)→ Starting VM...$(RESET)"
	@limactl start $(VM_NAME)
	@echo "$(GREEN)✅ VM started$(RESET)"

vm-clean: ## Delete the VM and free disk space
	@echo "$(RED)→ Deleting VM '$(VM_NAME)'...$(RESET)"
	@limactl delete --force $(VM_NAME) 2>/dev/null || true
	@echo "$(GREEN)✅ VM deleted$(RESET)"

vm-lima-list: ## List all Lima instances
	@limactl list

vm-full: vm-create vm-install vm-test ## Full cycle: create VM + install + verify
	@echo ""
	@echo "$(GREEN)🎉 Full test cycle complete$(RESET)"
	@echo "  → make vm-shell   to connect"
	@echo "  → make vm-clean   to clean up"

vm-reset: vm-clean vm-create vm-install vm-test ## Full reset: delete, recreate, install, and verify

