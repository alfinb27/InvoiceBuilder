.PHONY: setup validate-spec sync-spec check-sync test-core-ios test-data-ios test-sync-ios test-billing-ios test-pdf-ios test-ui-ios \
	test-app-ios test-ios pdf-samples build-ios test-core-android check

# Simulator for iOS tests; override with `make test-ios SIM="iPhone 16"`.
SIM ?= iPhone 17 Pro
# Where `make pdf-samples` writes the review PDFs.
OUT ?= build/pdf-samples
IOS_DESTINATION = platform=iOS Simulator,name=$(SIM)
# SQLiteData's macros (InvoiceSync) are trusted here; Xcode asks once per machine instead.
XCODEBUILD_FLAGS = -skipMacroValidation

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

test-sync-ios:    ## InvoiceSync: table mirrors vs schema, SyncEngine accepts the schema (macOS, CloudKit mock)
	swift test --package-path ios/Packages/InvoiceSync

test-billing-ios: ## InvoiceBilling: every purchase flow against a fake store (macOS)
	swift test --package-path ios/Packages/InvoiceBilling

test-pdf-ios:     ## InvoicePDF: the renderer, pagination, fonts (simulator)
	cd ios/Packages/InvoicePDF && xcodebuild -scheme InvoicePDF -destination '$(IOS_DESTINATION)' test

test-ui-ios:      ## InvoiceUI: view models, routers, image processing (simulator)
	cd ios/Packages/InvoiceUI && xcodebuild $(XCODEBUILD_FLAGS) -scheme InvoiceUI -destination '$(IOS_DESTINATION)' test

test-app-ios:     ## the app's UI smoke tests (simulator)
	xcodebuild $(XCODEBUILD_FLAGS) -project ios/InvoiceApp.xcodeproj -scheme InvoiceApp -destination '$(IOS_DESTINATION)' test

test-ios: test-core-ios test-data-ios test-sync-ios test-billing-ios test-pdf-ios test-ui-ios test-app-ios ## every iOS test

pdf-samples:      ## render one PDF per `pdf` fixture into OUT (for the CA / accountant review)
	cd ios/Packages/InvoicePDF && TEST_RUNNER_PDF_SAMPLES_OUT="$(abspath $(OUT))" xcodebuild -scheme InvoicePDF \
		-destination '$(IOS_DESTINATION)' test -only-testing:InvoicePDFTests/SampleDocumentsTests
	@echo "samples in $(OUT)"

build-ios:        ## build the app for the simulator
	xcodebuild $(XCODEBUILD_FLAGS) -project ios/InvoiceApp.xcodeproj -scheme InvoiceApp -destination 'generic/platform=iOS Simulator' build

test-core-android: ## run every fixture against :core:domain (Phase 7+)
	@if [ -f android/gradlew ]; then cd android && ./gradlew :core:domain:test; else echo "Android project not created yet (Phase 7)"; fi

check: validate-spec check-sync test-core-ios test-data-ios test-sync-ios test-billing-ios test-core-android
