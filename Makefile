.DEFAULT_GOAL := help
SHELL         := /bin/bash

DOCKER_FILE    := tests/docker/Dockerfile.test
DOCKER_COMPOSE := tests/docker/docker-compose.test.yml
TESTS_DIR      := tests

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

.PHONY: test test-configs test-functions test-init

test: ## Run all Bats tests
	bats $(TESTS_DIR)/

test-configs: ## Run config/file existence tests
	bats $(TESTS_DIR)/configs.bats

test-functions: ## Run shell function tests
	bats $(TESTS_DIR)/functions.bats

test-init: ## Run init.sh flag parsing tests
	bats $(TESTS_DIR)/init.bats

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

.PHONY: docker-build docker-test-bats docker-test-init docker-test-dotfiles

docker-build: ## Build all Docker test stages
	docker compose -f $(DOCKER_COMPOSE) build

docker-test-bats: ## Run Bats tests inside a Debian container
	docker build -f $(DOCKER_FILE) --target test-bats -t dotfiles-test-bats .

docker-test-init: ## Validate init.sh flag parsing in Docker
	docker build -f $(DOCKER_FILE) --target test-init -t dotfiles-test-init .

docker-test-dotfiles: ## Run dotfile-only install and verify symlinks in Docker
	docker build -f $(DOCKER_FILE) --target test-dotfiles -t dotfiles-test-dotfiles .

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
