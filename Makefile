.DEFAULT_GOAL := help
SHELL         := /bin/bash

DOCKER_FILE    := tests/docker/Dockerfile.test
DOCKER_COMPOSE := tests/docker/docker-compose.test.yml
TESTS_DIR      := tests

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

.PHONY: test test-configs test-functions test-init test-security test-ai test-ollama

# bats does not recurse (and -r would pick up the test_helper submodules' own
# suites), so every test subdirectory is listed explicitly.
BATS_DIRS := $(TESTS_DIR)/ $(TESTS_DIR)/ai/ $(TESTS_DIR)/ollama/

test: ## Run all Bats tests
	bats $(BATS_DIRS)

test-configs: ## Run config/file existence tests
	bats $(TESTS_DIR)/configs.bats

test-ai: ## Run local AI tooling tests
	bats $(TESTS_DIR)/ai/

test-ollama: ## Run Ollama script tests
	bats $(TESTS_DIR)/ollama/

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
	find . -type f \( -name "*.sh" -o -path "./scripts/ai/*" \) \
		-not -path "*/test_helper/*" -not -name "*.md" \
		-exec shellcheck --severity=warning --shell=bash --format=gcc {} +

validate: ## Validate YAML files with yamllint
	yamllint --strict .github/workflows/

# ──────────────────────────────────────────────────────────────────────────────
# Docker
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: docker-build docker-test-bats docker-test-init docker-test-dotfiles docker-test-base docker-test-security docker-test-security-full docker-test-kubernetes docker-test-full

docker-build: ## Build all Docker test stages
	docker-compose -f $(DOCKER_COMPOSE) build

docker-test-bats: ## Run Bats tests inside a Debian container
	docker build -f $(DOCKER_FILE) --target test-bats -t dotfiles-test-bats .

docker-test-init: ## Validate init.sh flag parsing in Docker
	docker build -f $(DOCKER_FILE) --target test-init -t dotfiles-test-init .

docker-test-dotfiles: ## Run dotfile-only install and verify symlinks in Docker
	docker build -f $(DOCKER_FILE) --target test-dotfiles -t dotfiles-test-dotfiles .

docker-test-base: ## Run the base profile (lite mode) and verify its tools in Docker
	docker build -f $(DOCKER_FILE) --target test-base -t dotfiles-test-base .

docker-test-security: ## Run security profile and verify configs in Docker
	docker build -f $(DOCKER_FILE) --target test-security -t dotfiles-test-security .

docker-test-security-full: ## Install CrowdSec and the audit tools (full-mode security) in Docker
	docker build -f $(DOCKER_FILE) --target test-security-full -t dotfiles-test-security-full .

docker-test-kubernetes: ## Run setup-kubernetes.sh on a bare system, then in full mode from an old kubectl channel, in Docker
	docker build -f $(DOCKER_FILE) --target test-kubernetes -t dotfiles-test-kubernetes .

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
