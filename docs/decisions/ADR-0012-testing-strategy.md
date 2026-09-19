# ADR-0012: Testing strategy

- **Status:** Accepted
- **Date:** 2026-09-19

## Decision
- **Core:** table-driven tests over every file in `spec/fixtures/` (tax, numbering, validation, words, format,
  status, backup) — `swift test` on macOS and `./gradlew :core:domain:test` on the JVM. Fixture count = parity metric.
- **Data:** migration tests (GRDB `DatabaseMigrator`, Room `MigrationTestHelper`); repositories on in-memory DBs.
- **View models:** Swift Testing with fakes; JUnit + Turbine + kotlinx-coroutines-test.
- **PDF:** text extraction vs fixtures + image snapshots (swift-snapshot-testing; Roborazzi on Robolectric).
- **UI:** a few smoke flows (XCUITest; Compose UI tests), iPhone + iPad, phone + tablet + foldable.
- **Human review:** an Indian CA and a UK accountant review the tax fixtures before Phase 2a completes.
