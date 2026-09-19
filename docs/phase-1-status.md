# Phase 1 status

- **As of:** 2026-09-19
- **Summary:** the iOS data layer, the setup screens and the adaptive iPhone/iPad shell are built and tested on
  simulators. Still to do: the TestFlight-internal build (needs the Apple account, bundle ID and signing team) and a
  few on-device checks.

## Tasks (plan § Phase 1)

| # | Task | Status | Evidence |
|---|---|---|---|
| 1 | `InvoiceCore` models: Money, LocalDate, domain types | ✅ | `ios/Packages/InvoiceCore/Sources/InvoiceCore/{Money,Dates,Models}` |
| 2 | Load `TaxConfig` from the bundle | ✅ | `TaxConfigStore`; `SpecLoadingTests` (bundled copy byte-equal to `spec/`) |
| 3 | GSTIN and VAT validators pass their fixtures | ✅ 19/19 | `FixtureTests.taxID` |
| 4 | `InvoiceData`: migrator running `0001`, records, repositories, `ValueObservation` streams | ✅ | `AppDatabase` runs the spec SQL; `MigrationTests` (structurally equal to `schema.sql`); `RepositoryTests` |
| 5 | `AppDependencies` | ✅ | `InvoiceUI/App/AppDependencies.swift` (on-disk, in-memory, `-inMemory` / `-seed IN\|GB`) |
| 6 | Onboarding: country → registration → business → tax ID → bank/UPI → logo and signature | ✅ | 5 steps, live GSTIN/VAT validation, state and PAN from the GSTIN, one-transaction Finish |
| 7 | Client list, search and editor (B2B/B2C, state picker) | ✅ | Archive/restore, delete (tombstone), duplicate tax ID warning |
| 8 | Catalogue editor (HSN/SAC, unit, rate filtered by config and date, inclusive price) | ✅ | Rates in force today, warning for a retired rate, HSN digit hint by turnover tier |
| 9 | Settings: numbering series, defaults | ✅ | Plus business profile, custom rates (GENERIC), logo and signature, About |
| 10 | Design system in `InvoiceUI` | ✅ | `Theme` from `spec/design/tokens.json`, form components |
| 11 | Adaptive shell: `TabView` `.sidebarAdaptable` + `NavigationSplitView`; routers own navigation | ✅ desk · 🔲 manual resize pass | `AppRouter`, `ListDetailRouter`, `RouterTests`; screenshot tours on iPhone 17 Pro and iPad Pro 13" |
| 12 | PencilKit signature → transparent PNG asset; logos as asset rows | ✅ desk · 🔲 finger/Pencil on a device | `Media/SignaturePad.swift`, `Media/ImageProcessing.swift` |
| 13 | `DeviceState` with a generated device id | ✅ | `GRDBDeviceStateRepository.loadOrCreate` |

**Spec first:** `spec/setup.md` (new, normative for all of the above); fixture kinds `field` (41 cases) and `input`
(29 cases); `make sync-spec` now also bundles the DB migrations into `InvoiceData`.

## Definition of done

| Criterion | State |
|---|---|
| CRUD for all three entities | ✅ business (create in onboarding, edit in Settings), clients and items (create, read, update, archive, delete) |
| Validators and config-loading fixtures green | ✅ 127 fixture cases: validation 19, field 41, input 29, format 25, numbering 13 |
| In-memory DB tests | ✅ 14 tests: schema parity, round trips, NULL clearing, tombstones, observation, transactional rollback |
| VoiceOver labels on every control | ◐ labelled in code (fields, icon buttons, image wells, colour swatches); on-device VoiceOver pass to do |
| No Swift 6 concurrency warnings | ✅ Swift 6 language mode everywhere; zero warnings from project sources |

## Test counts

| Command | Tests | Where |
|---|---|---|
| `make test-core-ios` | 61 (127 fixture cases) | macOS, `swift test` |
| `make test-data-ios` | 14 | macOS, `swift test` |
| `make test-ui-ios` | 20 (view models, routers, image processing) | iOS 27 simulator |
| `make test-app-ios` | 5 UI tests (3 smoke flows, 2 screenshot tours) | iOS 27 simulator, iPhone and iPad |

The fixture parity metric is now **127 of 254** on iOS. The remaining kinds (tax, rounding, distribute, words,
status, UPI) belong to Phase 2a.

## Found and decided during Phase 1

1. **Open value lists:** stored enums (`DocumentType`, `ItemKind`, `TaxCategory`, …) are open `RawRepresentable`
   structs, so values written by a newer app version still decode (repo rule 5).
2. **Custom rate ids:** the short id (`r` + 8 hex digits) could collide; `spec/setup.md` §7 now falls back to all 32
   hex digits.
3. **Tests by layer:** xcodebuild does not run local package test targets from the app's scheme or test plan, and
   simulator-hosted tests that read the repo under `~/Desktop` hit macOS folder privacy prompts. So `InvoiceCore` and
   `InvoiceData` run with `swift test`, `InvoiceUI` from its package directory, and the app scheme runs the UI tests
   (`ios/CLAUDE.md`).
4. **Phase 0 carry-over:** the sync spike (GRDB 7.11.1 + SQLiteData 1.12.0) now compiles with Xcode 27. The
   two-device run is still to do.

## Your next actions

1. **Finish Xcode's setup:** `sudo xcodebuild -runFirstLaunch` and `sudo xcode-select -s /Applications/Xcode.app`.
   Until then the release Xcode can't run simulators; the simulator runs above used Xcode-beta.
2. **TestFlight-internal build:** choose the bundle ID (`docs/product/naming.md`; the project uses the placeholder
   `app.invoicebuilder.invoices`) and set the development team. Then archive and upload.
3. **iPad resize pass:** in Clients, Items, Settings and onboarding, resize the window between compact and regular
   widths. Selection, open sheets and typed onboarding answers should survive.
4. **On a device:** draw a signature with a finger and with Apple Pencil, pick a HEIC photo as the logo, and do a
   VoiceOver pass of onboarding and the editors.
5. **Still open from Phase 0:** accounts (Apple, Google Play), CA and accountant reviews, the two-device sync run,
   pushing the repo to GitHub (the `spec` and `ios` workflows run then).

**Next:** Phase 2a, the tax engine and document core, with no UI.
