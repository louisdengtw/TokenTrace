APP_NAME    := TokenTrace
BUILD_APP   := build/$(APP_NAME).app
INSTALLED   := /Applications/$(APP_NAME).app

.PHONY: help build install run test clean

help: ## Show available targets
	@printf "Usage: make <target>\n\nTargets:\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	    | awk -F':.*## ' '{printf "  \033[36m%-9s\033[0m %s\n", $$1, $$2}'

build: ## Build universal .app via tools/build-app.sh
	@./tools/build-app.sh

install: build ## Build, then copy to /Applications/
	@rm -rf "$(INSTALLED)"
	@cp -R "$(BUILD_APP)" "$(INSTALLED)"
	@printf "Installed to %s\n" "$(INSTALLED)"

run: install ## Build, install, then relaunch (kills any prior instance)
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@sleep 0.3
	@open "$(INSTALLED)"

test: ## Run swift test
	@swift test

clean: ## Remove .build/ and build/ artifacts
	@rm -rf .build build
	@printf "Cleaned .build/ and build/\n"
