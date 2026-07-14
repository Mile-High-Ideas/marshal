# marshald — build / run / test
SHELL := /bin/bash
# Default to the hardware-free mock config so `make run` works with nothing
# plugged in; pass CONFIG=... for a real device config.
CONFIG ?= marshald.mock.toml

.DEFAULT_GOAL := build
.PHONY: build run test fmt vet

build: ## Build all packages
	go build ./...

run: ## Run the daemon (default: hardware-free mock). Override: make run CONFIG=path/to.toml
	go run ./cmd/marshald -config $(CONFIG)

test: ## Run all tests
	go test ./...

fmt: ## Format
	gofmt -w .

vet: ## Vet
	go vet ./...
