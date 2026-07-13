# marshal — USB discovery kit
# Run these on the macOS host that has the hardware (Shane's Mac).
#
#   make ecumaster   scan the ECUMaster USB->CAN cable
#   make aim         scan the AiM SW4 (must be powered!)
#   make ethernet    scan the USB->Ethernet adapter (Life Racing)
#   make host        capture Mac + Parallels info only
#   make bundle      zip all results to send back
#
SHELL := /bin/bash

.DEFAULT_GOAL := help

.PHONY: help host ecumaster aim ethernet scan bundle clean

help: ## Show this help
	@printf '\nmarshal USB discovery kit\n\n'
	@awk 'match($$0,/^[a-zA-Z_-]+:/){t=substr($$0,RSTART,RLENGTH-1); if($$0 ~ /## /){d=$$0; sub(/^.*## /,"",d); printf "  \033[36m%-10s\033[0m %s\n",t,d}}' $(MAKEFILE_LIST)
	@printf '\nTypical run: make ecumaster  ->  make aim  ->  make ethernet  ->  make bundle\n\n'

ecumaster: ## Scan the ECUMaster USB->CAN cable (USB-powered; no car needed)
	@./scan.sh ecumaster

aim: ## Scan the AiM SW4 (MUST be powered with 12V — bench harness or car)
	@./scan.sh aim-sw4

ethernet: ## Scan the USB->Ethernet adapter used for Life Racing
	@./scan.sh ethernet-adapter

host: ## Capture Mac host + Parallels environment info only
	@./scan.sh --host-only

scan: ## Scan any device by name: make scan NAME=whatever
	@./scan.sh "$(NAME)"

bundle: ## Zip all results in out/ into one file to send back
	@./scan.sh --bundle

clean: ## Delete all captured results and bundles
	@rm -rf out marshal-discovery-*.tar.gz && echo "Cleaned."
