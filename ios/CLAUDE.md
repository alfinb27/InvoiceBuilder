# iOS / iPadOS app rules

Read the root `CLAUDE.md` first. This file adds iOS-specific conventions.

## Stack

- Swift 6 language mode, strict concurrency. Minimum iOS/iPadOS 18. Universal app (iPhone + iPad).
- SwiftUI; `@Observable @MainActor` view models holding one `State` value each; one-way data flow.
- GRDB (`DatabasePool`, WAL) for persistence; SQLiteData sync layer (inside `InvoiceSync` only) for iCloud.
- StoreKit 2 (`InvoiceBilling`). PDFKit / `UIGraphicsPDFRenderer` / WebKit per the PDF ADR.
- Dependencies are limited to GRDB, SQLiteData and `swift-snapshot-testing` (tests). Anything else needs an ADR.

## Layout

| Path | What |
|---|---|
| `InvoiceApp.xcodeproj` | App target + UI test target only. Synchronized folders (`App/`, `AppUITests/`): add a file by creating it in the folder. Local packages are referenced from the project. |
| `App/` | `@main` (thin: `AppRootView(model: AppModel.launch())`), assets, privacy manifest. |
| `App-Info.plist` | Keys that have no build setting (single-window scene manifest); everything else is `INFOPLIST_KEY_*`. |
| `AppUITests/` | XCUITest smoke flows and the screenshot tour. |
| `Packages/` | All code (below). |

## Packages (`ios/Packages/`)

| Package | Rule |
|---|---|
| `InvoiceCore` | Pure Swift + Foundation. No UIKit/SwiftUI/GRDB imports. Money, dates, tax configs, `TaxEngine` (`Tax/`), validators, numbering + `NumberAllocator`, formatting, domain models, **setup rules** (`Setup/`, `spec/setup.md`), **document rules** (`Documents/`: `DocumentRules`, `LinePricing`, `LineItemRules`, per `spec/documents.md`) and the repository/service protocols. |
| `InvoiceData` | GRDB: `AppDatabase` runs the bundled `spec/schema/db/migrations/*.sql` verbatim; records (one per table); repository and service implementations (`GRDBDocumentService` = `IssueDocument`, duplicate, convert, delete draft, each one transaction). |
| `InvoicePDF` | The renderer: Core Text + `UIGraphicsPDFRenderer` drawing the `PDFDocumentModel` that `InvoiceCore/PDF` builds, laid out by `spec/pdf/layout/*.json`. No database, no view models — a request in, `Data` out. |
| `InvoiceBilling` | StoreKit 2 + `EntitlementService` implementing `spec/billing.md`. (Phase 5) |
| `InvoiceSync` | SQLiteData sync engine behind a `SyncService` protocol. `DeviceState` is never synced. (Phase 4b) |
| `InvoiceUI` | Design system (from `spec/design/tokens.json`) + feature screens (onboarding, invoices/quotes builder, clients, items, settings) + the adaptive shell, `AppModel`, `Session`, routers, `AppDependencies` and `InvoiceCommands` (menu bar + keyboard shortcuts). |

## Conventions

- Core types are `Sendable` value types. Pass IDs, not records, across actors.
- **Rules live in core, screens render them.** A view model holds a draft (`ClientDraft`, `BusinessDraft`, …) and asks
  the core rules (`ClientRules`, `BusinessRules`, `DocumentRules`, `LineItemRules`, …) what to show, what is wrong
  and what to save. Android ports the same types. New behaviour goes into `spec/setup.md` / `spec/documents.md`
  (+ fixtures when it is a pure function) first.
- Stored value lists (`DocumentType`, `ItemKind`, `TemplateID`, `TaxCategory`, …) are open `RawRepresentable`
  structs, not enums, so a value written by a newer app version (synced or restored) still decodes.
- Every screen must work from compact to regular width; navigation state lives in routers (`AppRouter`,
  `ListDetailRouter`, `DocumentsRouter`), never in views, so it survives iPad window resizing and size-class changes.
- Drafts autosave (500 ms debounce, plus on leaving the screen and going to the background; saves are chained so
  `flush()` returns only when everything is written). Never keep unsaved invoice data only in memory. (Setup forms
  save explicitly.)
- **Totals only come from `TaxEngine.compute`.** Screens render `ComputedDocument`; drafts recompute on every edit,
  issued documents show their stored result and are never recomputed.
- InvoiceUI files that import SwiftUI must write `InvoiceCore.Document` (SwiftUI also declares a `Document`).
- Money: `Money(minorUnits: Int64, currency: CurrencyCode)`. Typed amounts go through `MoneyInput.parse`, decimals
  through `DecimalInput.parse` / `DecimalString.parse`, never `Decimal(string:)` directly (it accepts `"1.5abc"`).
  Display text comes from `SpecFormatter` (deterministic), not `NumberFormatter`.
- `UUID().uuidString` is uppercase; ids come from `IDGenerator` (lowercase). Time comes from `TimeSource`.
- **GRDB:** repositories `save` by updating an existing id and inserting a new one; never a plain `INSERT` of an id
  that exists. Deletes write `deleted_at` (tombstones); every read filters `deleted_at IS NULL` (`Record.live`).
  JSON columns hold the domain JSON (camelCase keys). Column-name constants are `DBColumns` (GRDB 7 reserves
  `Columns`).
- View models get dependencies through `init` (`AppDependencies` / `Session`); tests use
  `AppDependencies.inMemory(time:ids:)` with `TimeSource.fixed` and `IDGenerator.sequential()`.
- Launch arguments (UI tests, screenshots, manual QA): `-inMemory` (empty database), `-seed IN` / `-seed GB`
  (onboarded sample business with clients and items). Both leave the real database untouched.

## Commands

```sh
make test-core-ios      # swift test InvoiceCore: every implemented fixture kind + unit tests (no simulator)
make test-data-ios      # swift test InvoiceData: migrations == schema.sql, repositories (no simulator)
make test-pdf-ios       # InvoicePDF: the renderer, pagination and fonts (simulator)
make test-ui-ios        # InvoiceUI view models on a simulator (SIM="iPhone 17 Pro" by default)
make test-app-ios       # XCUITest smoke flows + screenshot tour
make test-ios           # all of the above
```

- `InvoiceUI` and `InvoicePDF` tests run from the package directory (`cd Packages/InvoiceUI && xcodebuild -scheme
  InvoiceUI …`): xcodebuild does not run a local package's test targets from the app's scheme or test plan.
- Full Xcode is required for the simulator suites; Command Line Tools are enough for `swift test` on `InvoiceCore`
  and `InvoiceData`. A freshly installed Xcode must finish its first launch (`sudo xcodebuild -runFirstLaunch`)
  before simulators work; until then another installed Xcode can be used with `DEVELOPER_DIR=…`.
- Switching toolchains (Command Line Tools ↔ Xcode) on the same package: delete its `.build/` first; stale
  products make the Swift Testing macros "not found".
- **CI is the stricter compiler.** GitHub's `macos-15` runner builds with Xcode 16.4 (iOS 18.5 SDK), which is older
  than a local beta: a type the newer SDK marks `Sendable` may not be marked there, and Swift 6 then rejects code
  that built locally (`CIContext` did). A green local build is not proof; the PR check is.
- Offline builds: `xcodebuild … -clonedSourcePackagesDirPath <dir> -disableAutomaticPackageResolution
  -skipPackageUpdates`, with `<dir>` seeded from a SwiftPM `.build` (`checkouts/`, `repositories/`).
