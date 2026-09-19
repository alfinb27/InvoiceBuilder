.PHONY: setup validate-spec sync-spec check-sync test-core-ios test-data-ios test-ui-ios test-app-ios test-ios \
	build-ios test-core-android check

# Simulator for iOS tests; override with `make test-ios SIM="iPhone 16"`.
SIM ?= iPhone 17 Pro
IOS_DESTINATION = platform=iOS Simulator,name=$(SIM)

setup:            ## install spec tooling (once)
	npm ci --prefix spec/tools --no-audit --no-fund

validate-spec:    ## schemas, configs, DB schema, samples, fixture consistency
	node spec/tools/validate.mjs

sync-spec:        ## copy runtime spec files into the app bundles
	spec/tools/sync-spec.sh

check-sync:       ## fail if bundled spec copies are stale
	spec/tools/sync-spec.sh --check

test-core-ios:    ## InvoiceCore: every implemented fixture kind + unit tests (macOS, no simulator)
	swift test --package-path ios/Packages/InvoiceCore

test-data-ios:    ## InvoiceData: migrations vs schema.sql, repositories (macOS, no simulator)
	swift test --package-path ios/Packages/InvoiceData

test-ui-ios:      ## InvoiceUI: view models, routers, image processing (simulator)
	cd ios/Packages/InvoiceUI && xcodebuild -scheme InvoiceUI -destination '$(IOS_DESTINATION)' test

test-app-ios:     ## the app's UI smoke tests (simulator)
	xcodebuild -project ios/InvoiceApp.xcodeproj -scheme InvoiceApp -destination '$(IOS_DESTINATION)' test

test-ios: test-core-ios test-data-ios test-ui-ios test-app-ios ## every iOS test

build-ios:        ## build the app for the simulator
	xcodebuild -project ios/InvoiceApp.xcodeproj -scheme InvoiceApp -destination 'generic/platform=iOS Simulator' build

test-core-android: ## run every fixture against :core:domain (Phase 7+)
	@if [ -f android/gradlew ]; then cd android && ./gradlew :core:domain:test; else echo "Android project not created yet (Phase 7)"; fi

check: validate-spec check-sync test-core-ios test-data-ios test-core-android
