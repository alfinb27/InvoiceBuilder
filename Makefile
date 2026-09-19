.PHONY: setup validate-spec sync-spec check-sync test-core-ios test-core-android check

setup:            ## install spec tooling (once)
	npm ci --prefix spec/tools --no-audit --no-fund

validate-spec:    ## schemas, configs, DB schema, samples, fixture consistency
	node spec/tools/validate.mjs

sync-spec:        ## copy runtime spec files into the app bundles
	spec/tools/sync-spec.sh

check-sync:       ## fail if bundled spec copies are stale
	spec/tools/sync-spec.sh --check

test-core-ios:    ## run every fixture against InvoiceCore (Phase 1+)
	@if [ -d ios/Packages/InvoiceCore ]; then swift test --package-path ios/Packages/InvoiceCore; else echo "InvoiceCore not created yet (Phase 1)"; fi

test-core-android: ## run every fixture against :core:domain (Phase 7+)
	@if [ -f android/gradlew ]; then cd android && ./gradlew :core:domain:test; else echo "Android project not created yet (Phase 7)"; fi

check: validate-spec check-sync test-core-ios test-core-android
