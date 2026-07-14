# marshald — build / run / test
SHELL := /bin/bash
CONFIG ?= marshald.toml

.DEFAULT_GOAL := build
.PHONY: build run test fmt vet

build: ## Build all packages
	go build ./...

run: ## Run the daemon: make run CONFIG=path/to.toml
	go run ./cmd/marshald -config $(CONFIG)

test: ## Run all tests
	go test ./...

fmt: ## Format
	gofmt -w .

vet: ## Vet
	go vet ./...
