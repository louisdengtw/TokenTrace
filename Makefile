APP_NAME    := TokenTrace
BUILD_APP   := build/$(APP_NAME).app
INSTALLED   := /Applications/$(APP_NAME).app

DEV_APP_NAME    := TokenTraceDev
DEV_BUNDLE_ID   := dev.louisdeng.tokentrace.dev
DEV_BUILD_APP   := build/$(DEV_APP_NAME).app
DEV_INSTALLED   := /Applications/$(DEV_APP_NAME).app

.PHONY: help build install run dev dev-install dev-run test clean

help: ## Show available targets
	@printf "Usage: make <target>\n\nTargets:\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	    | awk -F':.*## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

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

dev: ## Build TokenTraceDev.app (separate bundle ID, runs alongside production)
	@APP_NAME=$(DEV_APP_NAME) BUNDLE_ID=$(DEV_BUNDLE_ID) ./tools/build-app.sh

dev-install: dev ## Build dev, then copy to /Applications/
	@rm -rf "$(DEV_INSTALLED)"
	@cp -R "$(DEV_BUILD_APP)" "$(DEV_INSTALLED)"
	@printf "Installed to %s\n" "$(DEV_INSTALLED)"

dev-run: dev-install ## Build dev, install, relaunch (only kills the dev instance)
	@pkill -x $(DEV_APP_NAME) 2>/dev/null || true
	@sleep 0.3
	@open "$(DEV_INSTALLED)"

test: ## Run swift test
	@swift test

clean: ## Remove .build/ and build/ artifacts
	@rm -rf .build build
	@printf "Cleaned .build/ and build/\n"
