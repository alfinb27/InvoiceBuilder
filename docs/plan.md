# Invoice App: Phased Implementation Plan (iOS first, then Android)

## 0. Context

You are a solo iOS developer building an offline-first invoicing app for sole traders, freelancers and small shops, starting in India and the UK. Both apps are native. They implement one shared **spec**: schemas, tax configs, PDF templates and golden test fixtures. That spec keeps tax behaviour identical on both platforms, turns the Android port into careful translation instead of reinvention, and means a new country is added as data. This document covers:
- the decisions, each with the options considered, the choice, and what would change my mind
- the architecture
- the data model
- the tax-config schema
- phases 0–8

### Interview answers built into the plan
| Topic | Your answer | Effect on the plan |
|---|---|---|
| Build/launch order | iOS first, launch iOS (UK + IN), then Android | Android is Phase 7. The Play account and closed-test groundwork start early (see 7c). |
| Extra tax scope in v1 | Exports/foreign currency, reverse charge, India composition, tax-inclusive prices | The tax engine (Phase 2a) grows by about 5–7 iOS days, needs more fixtures and a professional review |
| iOS storage | GRDB plus a few vetted deps | SQLite on both platforms, with one schema and numbered SQL migrations in `spec/` |
| v1 extras | UPI QR, quotes/estimates, local overdue reminders | A generic *Document* model from day one; QR in Phase 3; reminders in Phase 4 |
| Not chosen | Hindi UI | The v1 UI is English with en-GB/en-IN formatting. PDFs still render Devanagari that users type in (bundled fallback font). |
| iPadOS | A universal iPhone + iPad app in v1 | Adaptive layouts from Phase 1, a two-pane builder with live PDF preview, keyboard/pointer/drag-and-drop support. Minimum OS raised to 18 (D10, D14). Android tablets and foldables get the same treatment in Phase 7. |
| iPhone ↔ iPad data | iCloud sync (Apple devices only) in v1 | New D15 and Phase 4b. Adds SQLiteData's CloudKit sync on top of GRDB, and numbering becomes device-owned series. Android stays local-only in v1. |
| Mac | Decide at launch | A one-day "Designed for iPad" evaluation at the Phase 6 gate |

### Assumptions (correct me at review)
- **Minimum iOS/iPadOS 18.** It supports the same devices as 17 (XS/XR and later) and adds the adaptive `TabView` that becomes a sidebar on iPad. **Android minSdk 26, target/compile SDK 36.** Reasons are in D10.
- One business per user in v1. Every table carries `business_id`. With sync, two devices set up offline can each create a business, so a minimal "active business" picker exists but stays hidden unless there is more than one (D15).
- A4 paper for both IN and UK. Paper size is a per-country config value.
- The free tier is **15 issued invoices over the lifetime of the install**. Drafts and quotes never count. Details in D8.
- No third-party analytics or crash SDKs in v1, so the privacy label can say "Data Not Collected". See D11.
- Exchange rates for foreign-currency invoices are typed in by the user (no network in v1).
- Effort is in **dev-days**: about 6 focused hours of a solo developer working with Claude Code.

### Headline recommendations (where I change or sharpen your assumptions)
1. **Keep two native apps**, but put *all* business logic in a platform-neutral core module on each side: the `InvoiceCore` Swift package and the `:core:domain` pure-Kotlin module. Shared golden fixtures prove the two behave identically. No Kotlin Multiplatform for now (D1).
2. **GRDB (SQLite) instead of SwiftData**, as you chose, so both apps share one relational schema (D3).
3. **A generic `Document`** (invoice | quote | credit note later) from day one. Quotes are nearly free, and credit notes and recurring invoices later need no migration.
4. **Status is derived, not stored.** Store the lifecycle (`draft/issued/void`), `sentAt` and payments, then *compute* sent / partially paid / paid / overdue. No background job has to flip statuses.
5. **Numbers are allocated when an invoice is issued**, not when the draft is created. GST requires consecutive numbers, and deleted drafts would otherwise leave gaps.
6. **Money:** every stored amount is an `Int64` in minor units. Rates, quantities and intermediate maths use Decimal (Foundation `Decimal` / `java.math.BigDecimal`). Rounding is defined **by meaning in the spec**, not by library enum names, which differ between platforms.
7. **Issued documents are frozen snapshots.** Seller, buyer, lines and tax results are copied onto the document, and old invoices are never recalculated when rates change. India's September 2025 GST restructuring (12%/28% slabs mostly removed, 40% added) shows why this matters.
8. **A backup is one portable JSON file** (with the images base64-encoded). An iOS backup restores on Android, so users can move platforms.
9. **The PDF spike should favour shared HTML/CSS templates plus one shared `render.js`**, with the final choice made by a scored rubric (D6).
10. **Add a few cheap compliance items** you didn't list: a signature image (GST Rule 46), a supply date/tax point, amount in words (standard on Indian invoices), and company number and registered office for UK Ltd companies.
11. **Price check:** £0.99 nets about £0.70 after VAT and a 15% store commission, and ₹49 nets about ₹35. Price is set in the stores, not in code, so it can be changed after launch. Consider £1.99–2.99 / ₹99–149.
12. **iPad is designed in from Phase 1, not bolted on later.** Every screen gets a regular-width layout. The invoice builder on iPad is a form next to a live PDF preview, which is the iPad's best feature and useful for shops that invoice from a counter iPad.
13. **Sync-safe schema from day one.** Synced tables can't rely on UNIQUE constraints (other than the primary key), and migrations must be additive after release. Invoice numbers stay unique because **each device issues from its own series**, which GST ("one or multiple series") and HMRC ("one or more series") both allow (D15).

## 1. Decision records
Each decision gets an ADR in `docs/decisions/` during Phase 0. The format is **options → choice → why → what would change my mind**.

### D1. Build order and how code is shared
- **Options:**
  - (a) Two native apps, each implementing a shared spec, kept equal by golden fixtures
  - (b) Kotlin Multiplatform (KMP) core (tax engine, models, maths) with native SwiftUI/Compose UIs
  - (c) Compose Multiplatform, Flutter or React Native (one UI for both)
  - (d) Android first
- **Choice:** (a), building iOS first.
- **Why:**
  - The logic that has to be identical is small, roughly 1.5–2.5k lines per platform. Because the tax rules live in JSON, the engine is a *config interpreter*, not a rulebook.
  - Golden fixtures turn "identical" into a CI check.
  - Claude Code ports Swift to Kotlin well when the fixtures act as the answer key, so writing the core twice is now cheap.
  - KMP would make you write the core in Kotlin *first* (your weaker language), add Gradle to the iOS build, and bring Swift interop friction. Swift Export and SKIE have improved, but the friction is real.
  - Option (c) throws away your SwiftUI skills and makes the UI feel less native on both platforms.
  - iOS first means the product gets defined with your fastest tools, and Android then benefits from real feedback.
- **Would change my mind:**
  - The shared logic grows a lot (sync conflict resolution, reports engine, recurring schedules) or a third client appears (web/desktop). Then move the *core* to KMP, and the fixtures become its tests unchanged.
  - Android traction in India clearly beats iOS after launch. Then Phase 8 should be Android-led.

### D2. Architecture pattern (both platforms)
- **Options:**
  - (a) MVVM with one-way data flow: screen state struct, intent methods, observable view model
  - (b) The Composable Architecture (TCA) on iOS with an MVI library on Android
  - (c) "MV" (views bind straight to @Observable models, no view models)
  - (d) VIPER/Clean with full use-case layers
- **Choice:** (a) on both platforms, plus a *thin* domain-service layer used only where an operation spans several repositories (e.g. `IssueDocument`: allocate number → freeze snapshots → count toward the free tier → schedule reminder, all in one transaction).
- **Why:**
  - Android's official architecture guide *is* this pattern (`ViewModel` + `StateFlow<UiState>` + events). An iOS `@Observable` view model maps one-to-one to a Jetpack `ViewModel`, which makes the port mechanical.
  - View models can be tested without UI.
  - TCA adds a learning curve, compile time and a large dependency, and has no Android equivalent.
  - Option (c) pushes logic into views on iOS and has no clean Android counterpart.
- **Would change my mind:** state and side effects get hard to reason about. The likely trigger is sync, where TCA (iOS) and an MVI library (Android) earn their cost.

### D3. Persistence
- **Options (iOS):**
  - SwiftData
  - Core Data
  - GRDB
  - SQLiteData (Point-Free, built on GRDB)
- **Options (Android):**
  - Room
  - SQLDelight
  - Realm (deprecated for Kotlin)
- **Choice:** **GRDB on iOS and Room on Android.** Both are SQLite, and `spec/schema/db/` holds the canonical DDL plus numbered migrations `0001_init.sql`, `0002_…`.
- **Why:**
  - The same engine and schema on both sides means the same queries, constraints and migration steps. Porting the data layer becomes a transliteration.
  - Invoices are financial records, so you want explicit, testable migrations, foreign keys, `CHECK` constraints, and number allocation inside a single write transaction. Synced tables can't have UNIQUE constraints other than the primary key; D15 explains how number uniqueness is guaranteed instead.
  - GRDB records are `Sendable` structs, which suits Swift 6 strict concurrency. SwiftData's `@Model` classes are tied to a context/actor.
  - Future reports need `SUM`/`GROUP BY`, which `#Predicate` cannot express.
  - Room is Google's default: best documentation, checks SQL at compile time, exports its schema as JSON for migration tests, and supports KMP if D1 ever flips.
  - SQLDelight would let you feed the spec SQL in directly, but it has fewer tutorials. That matters while you are learning Android.
- **Parity check:** Room exports its schema JSON (`room.schemaLocation`). A small script in `spec/tools/` compares it against `schema.sql` in CI.
- **Would change my mind:** you want Apple-only iCloud sync soon with minimal work. **That has now happened:** sync is in v1, so SQLiteData's CloudKit sync engine is added *on top of* GRDB (D15). GRDB migrations, SQL parity with Room and the repositories stay as they are.

### D4. Dependency injection
- **Options (iOS):**
  - A hand-written `AppDependencies` container passed through the SwiftUI `Environment`
  - swift-dependencies
  - Factory/Resolver
- **Options (Android):**
  - Manual `AppContainer` (Google documents this for small apps)
  - **Hilt**: Google's annotation-processing DI, the Android counterpart of a compile-time DI container. Nothing like it is standard on iOS.
  - **Koin**: a runtime service-locator DSL
- **Choice:** manual injection on both platforms. On iOS, `AppDependencies` is built in `App.init`, and view models get their dependencies through `init`. On Android, `AppContainer` is created in the `Application` subclass (the rough equivalent of `AppDelegate`), and view models are built with `viewModelFactory { initializer { … } }`.
- **Why:**
  - The object graph is small (about 10 services).
  - The same mental model works on both platforms, with no annotation-processing "magic" to learn in your first Android project and faster Gradle builds.
  - Tests just pass fakes in.
- **Would change my mind:** the Android graph passes about 15 view models, or WorkManager workers need injected dependencies (recurring invoices, sync). Then move to Hilt (`hiltViewModel()`, `HiltWorkerFactory`); it is a mechanical migration.

### D5. State management and navigation
- **iOS:**
  - `@Observable @MainActor` view models, each holding one `State` value
  - GRDB `ValueObservation` exposed as an `AsyncSequence` and consumed in `.task {}`
  - Forms edit a value-type draft (`DocumentDraft`), and the pure `TaxEngine.compute` runs on every change (microseconds)
  - Drafts autosave after a 500 ms debounce
  - `NavigationStack(path:)` with a per-tab `Router` (`@Observable` path array)
- **Android:**
  - `ViewModel` exposes `StateFlow<UiState>` built with `combine(daoFlows…).stateIn(viewModelScope, WhileSubscribed(5_000), initial)`
  - Compose reads it with `collectAsStateWithLifecycle()`
  - One-off effects (e.g. "show share sheet") are modelled as state that the UI consumes and clears. A `Channel` is a fallback.
- **Android navigation:**
  - **Options:** Navigation 3 (stable since late 2025, built for Compose) or Navigation Compose 2.x with type-safe `@Serializable` routes.
  - **Choice:** Navigation 3. You own the back stack as a plain observable list of route keys, exactly like `NavigationStack(path:)`, and it supports the predictive-back gesture (Android's preview of the previous screen while swiping back, similar to the iOS interactive pop).
  - **Would change my mind:** Nav3 blocks you on deep links or result passing. Then drop back to Nav 2 type-safe routes, which are fully supported.
- **Android-only concepts you must design for:**
  - **Configuration changes.** Rotation, dark-mode or locale switches *recreate the Activity* (roughly: the screen's host controller is thrown away and rebuilt). `ViewModel`s survive this; `remember {}` state does not, so use `rememberSaveable {}`.
  - **Process death.** In the background, Android can kill your process and later restore the back stack *without* your in-memory state. `SavedStateHandle` in the view model restores small keys such as the draft ID, and autosaving drafts to Room covers the rest.
  - iOS has neither problem in practice. Autosaving drafts on both platforms removes the whole class of bugs.

### D6. PDF approach (decided by the Phase 0 spike)
- **Option A: shared HTML/CSS templates.**
  - `spec/pdf/templates/<name>/template.html` + `styles.css`, plus one shared `render.js` that fills the DOM from a JSON "PDF view model".
  - **iOS:** off-screen `WKWebView` → `UIPrintPageRenderer` + `viewPrintFormatter()` → `UIGraphicsPDFRenderer`, which gives real page breaks. `createPDF` produces one tall page, so it is not used.
  - **Android:** off-screen `WebView` → `createPrintDocumentAdapter()` → write to a file. Saving a PDF *silently*, without the system print dialog, needs a known workaround: a helper class placed in the `android.print` package to reach package-private callbacks. That is the main risk.
  - **Pros:** templates written once; Claude Code can iterate on them in a desktop browser against fixture JSON; identical look on both platforms; a fifth template is just CSS.
  - **Cons:** WebKit and Chromium paginate differently at the edges; async, main-thread `WebView`; the Android workaround.
- **Option B: native drawing from a shared layout spec.**
  - **iOS:** `UIGraphicsPDFRenderer` + Core Text.
  - **Android:** `android.graphics.pdf.PdfDocument` + `Canvas` + `StaticLayout`. This is the direct equivalent of `UIGraphicsPDFRenderer` + Core Graphics text drawing.
  - Both render from a JSON layout spec, and you write pagination yourself.
  - **Pros:** deterministic, fast, no WebView, no workaround.
  - **Cons:** every template is implemented twice, and the two renderers drift slightly over time.
- **Rejected:**
  - Third-party PDF libraries per platform (TPPDF / OpenPDF / PdfBox-Android): different engines mean the output drifts, and iText is AGPL.
  - A shared Typst/Rust engine: 10–20 MB of binary plus FFI work, which is too heavy for a solo v1.
- **Rubric (weights):**

  | Criterion | Weight |
  |---|---|
  | Visual parity across platforms | 25 |
  | Pagination (60-line invoice, repeated table header, totals block kept whole, "Page x of y") | 20 |
  | Effort for 4 templates × 2 platforms | 20 |
  | Robustness, no private-API workarounds | 15 |
  | Speed and memory on a low-end Android (≤3 GB RAM) | 10 |
  | Selectable text, file size under 300 KB | 10 |

- **Prior:** A wins unless the silent Android export fails on any test API level (26 / 30 / 35–36) or takes more than 2 s on the low-end device.
- **Would change my mind:** those failures. If they happen, choose B, still with templates defined in `spec/pdf/layout/*.json`.

### D7. Money, numbers and dates
- **Options:**
  - Floating point (rejected: it cannot represent 0.1 exactly)
  - Decimal everywhere
  - Integer minor units everywhere
  - **A hybrid**
- **Choice: the hybrid.**
  - Every *stored* amount is `Int64` minor units plus an ISO-4217 currency. The exponent comes from `spec/reference/currencies.json` (INR/GBP = 2, JPY = 0, KWD = 3).
  - Rates (`"18"`, `"8.875"`) and quantities (`"1.5"` hours) are decimal *strings* in JSON and SQLite. They are parsed into `Decimal` / `BigDecimal` for the maths.
  - Intermediate values keep at least 20 significant digits. Values are rounded to minor units only at the points the country config names (line or invoice level).
- **Rounding** is spec'd by meaning: `halfAwayFromZero`, `halfEven`, `towardZero`.
  - Each platform implements one 20-line `round(_:scale:mode:)` function, and fixtures (including negative amounts and exact .5 boundaries) prove the two match.
  - Don't trust enum names: Foundation's `.plain` is half-away-from-zero, Java's `HALF_UP` happens to be the same, but `.down` and `DOWN` differ for negative numbers.
- **Kotlin gotchas to write into `android/CLAUDE.md`:**
  - `BigDecimal.equals` compares scale (`2.0 != 2.00`), so always use `compareTo`.
  - `divide()` without a scale and `RoundingMode` throws on non-terminating results.
- **Allocation:** invoice-level discounts, and splitting tax into CGST/SGST halves, use the **largest-remainder method** so the parts always add up to the whole.
- **Dates:**
  - Issue, supply and due dates are *calendar dates* stored as ISO strings (`"2026-09-19"`). A custom `LocalDate` struct on iOS mirrors `java.time.LocalDate`, so there are no timezone off-by-one errors.
  - Audit timestamps are `Int64` epoch milliseconds UTC.
  - UUIDs are stored as **lowercase** strings. Swift's `uuidString` is uppercase and Java's is lowercase, a classic cross-platform bug.

### D8. Billing and entitlements
- **Product:** one non-consumable, `unlimited_invoices`. On iOS that is a StoreKit 2 non-consumable; on Android a Play Billing "one-time product" (the same idea).
- **Options:** local-only validation (StoreKit 2 signed transactions are checked on the device) vs server validation (needs a backend, which is a non-goal).
- **Choice:** local.
  - **iOS:** `Transaction.currentEntitlements` at launch, a `Transaction.updates` listener (covers refunds via `revocationDate`, Ask to Buy and Family Sharing), and a "Restore purchases" button calling `AppStore.sync()`. App Review expects a restore option for non-consumables.
  - **Android:** Play Billing Library 8+ with automatic service reconnection and pending purchases enabled. `queryPurchasesAsync(INAPP)` runs on every start and resume, so reinstall restores automatically, and a "Refresh purchases" button is kept for parity.
- **Android differences, explained:**
  1. You **must acknowledge** a purchase within 3 days or Google automatically refunds it. StoreKit 2 has no equivalent, and `finish()` is not the same thing.
  2. **Pending purchases** are common in India (UPI or cash payment codes that complete later). Unlock only on `PURCHASED`, never on `PENDING`.
  3. You cannot create the in-app product in Play Console until an app bundle with the billing permission has been uploaded to a testing track. Upload early.
  4. Testing uses "license testers" and the internal track. The equivalents are StoreKit configuration files plus sandbox accounts.
- **Free-tier counter:**
  - Increments when a document of type invoice is *issued*. It never goes down, even if the invoice is voided or deleted.
  - Stored in SQLite *and* mirrored to the Keychain (iOS, which survives a reinstall in practice) and to Block Store or Auto Backup data (Android, best effort).
  - With iCloud sync on, the limit is checked against `max(local counter, issued invoices across all synced devices)`, so a second device doesn't reset it.
  - The purchase belongs to the Apple ID, so it unlocks every iPhone, iPad (and Mac) signed in to that account. It is not synced through our data.
  - Anti-piracy effort is deliberately small for a £1 product.
  - After the limit: users can still view, edit, share and export every existing document and create drafts and quotes. Only "Issue invoice" is behind the paywall.
- **Shared state machine** (`spec/billing.md`): `unknown → free(n) → limitReached → purchasing → pending(Android) → unlocked`, with `revoked → free`.
- **Would change my mind:** a subscription tier (e.g. cloud sync) arrives. That brings server notifications (App Store Server Notifications / Play Real-time Developer Notifications) and therefore a small backend.

### D9. Repo and project tooling
- **Options:**
  - A monorepo, or separate repos with the spec as a git submodule
  - For the Xcode project: plain `.xcodeproj` with synchronized folders, XcodeGen, or Tuist
- **Choice:**
  - **A monorepo**, so a spec change and both implementations land in one commit, with path-filtered CI.
  - **A plain Xcode project using synchronized (buildable) folders, with nearly all code in local Swift packages.** `Package.swift` is text that Claude Code edits safely, and the `.pbxproj` rarely changes.
- **How the spec reaches each app:**
  - Tests read fixtures straight from `spec/` (`#filePath` on iOS; Gradle `resources.srcDir("../../spec/…")` on Android, since Gradle can reference folders outside the module).
  - The runtime configs and templates the app bundles are copied by `make sync-spec`, and CI fails if the copies differ.
- **Would change my mind:** targets or configurations start changing often (app extensions, widgets). Then adopt Tuist.

### D10. Minimum OS versions
- **iOS/iPadOS 18.0 (raised from 17 once iPad was added).**
  - iOS 18 runs on the same devices as 17 (XS/XR and later), so only people who never updated miss out.
  - It adds `TabView(...).tabViewStyle(.sidebarAdaptable)`: a tab bar on iPhone and a sidebar on iPad from one declaration. That avoids hand-written switching between a tab view and a split view, and the navigation state lost when iPad windows are resized.
  - CKSyncEngine (used by the sync layer) needs 17 or later, so either minimum works for sync.
  - **Would change my mind:** India beta testers stuck on iOS 17. Then drop to 17 and hand-write the split/tab switching (+2 days).
- **Android minSdk 26 (Android 8.0).**
  - That covers about 97% of active devices.
  - It gives native `java.time` without "desugaring" (a Gradle step that backports newer Java APIs to old Android versions).
  - Current AndroidX libraries require 23 or higher anyway.
- **Android target/compile SDK 36.**
  - Play requires new apps and updates to target the latest-but-one API level each August.
  - Targeting 35 or higher forces **edge-to-edge** drawing (the app draws under the status and navigation bars and must handle insets, like iOS safe areas).
  - **Would change my mind:** India beta testers on API 24–25 devices. Then go to 24 with desugaring.

### D11. Crash reporting, analytics and privacy
- **Options:**
  - First-party only: Xcode Organizer + MetricKit on iOS; Play Console **Android vitals** (crashes and ANRs, "App Not Responding", which is a main-thread hang longer than 5 s)
  - Firebase Crashlytics
  - Sentry
  - TelemetryDeck (privacy-first analytics)
- **Choice:** first-party only in v1, plus the TestFlight / internal-track feedback channels.
  - "Your invoices never leave your phone" is a real selling point for a financial app.
  - Store privacy forms stay trivial: "Data Not Collected" on the App Store, and a minimal Play **Data safety** form (Android's version of the App Store privacy label).
- **Would change my mind:** beta crashes you cannot reproduce (Organizer data is opt-in and sampled). Then add Sentry (open-source SDKs on both platforms, can scrub personal data) at the Phase 6 gate and update the privacy labels.

### D12. Testing strategy
- **Core (the most important layer):**
  - Table-driven tests run *every* fixture in `spec/fixtures/`: tax, numbering, validators, amount-in-words, formatting, backup round-trips.
  - iOS runs them with `swift test` on the Mac, no simulator. Android runs them with `./gradlew :core:domain:test` on the JVM, no emulator.
  - The fixture count is the parity metric.
- **Data:**
  - Migration tests on both platforms: GRDB's `DatabaseMigrator` against an in-memory database; Room's `MigrationTestHelper` using the exported schema JSON.
  - Repository tests against an in-memory database.
- **View models:**
  - Swift Testing with fakes on iOS.
  - On Android, JUnit + **Turbine** (a small library for asserting on `Flow` emissions, the equivalent of collecting an `AsyncSequence` in a test) + `kotlinx-coroutines-test`.
- **PDF:**
  - Extract text (PDFKit / `PdfRenderer` plus text checks) and compare it with fixture expectations.
  - Image snapshots per template: `swift-snapshot-testing` on iOS; on Android, **Roborazzi**, which renders screenshots on the JVM through **Robolectric** (a simulated Android framework that runs on your Mac with no emulator; iOS has nothing like it).
- **UI:**
  - A few end-to-end smoke flows: XCUITest on iOS; the Compose UI test APIs on Android (in-process, closer to ViewInspector than to XCUITest).
- **Human review:**
  - An Indian CA and a UK accountant review the tax fixtures once, before Phase 2 is marked done. This is a paid half-day each and the cheapest insurance in the plan.

### D13. Backup, restore and reminders
- **Backup options:**
  - Rely on OS backups only
  - Copy the raw SQLite file
  - **A portable JSON export**
- **Choice:** all three layers, with JSON as the one users see.
  1. OS backups stay on: iCloud/device backup on iOS; Android **Auto Backup** (up to 25 MB to Google Drive, controlled by `dataExtractionRules`).
  2. **Export backup** writes `InvoiceBackup-YYYY-MM-DD.invoicebackup`: one JSON file matching `spec/schema/backup.schema.json`, with logo and signature images base64-encoded.
     - Zero dependencies. A zip would need ZIPFoundation on iOS.
     - It can be shared or saved to Files / Drive. On Android, saving goes through the **Storage Access Framework**, the system file picker (≈ `fileExporter` / `UIDocumentPickerViewController`).
  3. Before any restore or schema migration, the app automatically writes a safety snapshot to the app container.
  - Restore in v1 is "replace all", after validation and a preview of the counts. **With iCloud sync on, that replaces the data on every signed-in device**, so the confirmation says so explicitly, and every device keeps its own safety snapshot.
  - Raw SQLite copies are rejected because they tie backups to one schema version and one platform.
- **Reminders:**
  - **iOS:** can't reliably run background code, so each overdue reminder is *pre-scheduled* as a local notification (`UNCalendarNotificationTrigger`) at issue time or when the due date changes. iOS allows at most 64 pending, so only the nearest 50 are kept.
  - **Android:** can run background work reliably. **WorkManager**, the OS-managed job scheduler that survives reboots (a far more dependable cousin of `BGTaskScheduler`), runs a daily job that works out which invoices are overdue and posts grouped notifications.
    - This needs the `POST_NOTIFICATIONS` runtime permission on Android 13 and later (≈ `requestAuthorization`).
    - Some OEMs (Xiaomi/HyperOS, some Samsung builds) kill background work aggressively, so reminders there are best effort.

### D14. iPad support
- **Options:**
  - (a) iPhone-only now, iPad later
  - (b) a "stretched iPhone" iPad app
  - (c) a properly adaptive universal app
- **Choice:** (c), designed from Phase 1.
- **v1 iPad features:**
  - `TabView` `.sidebarAdaptable` plus `NavigationSplitView` list/detail per section
  - the builder as a form beside a live PDF preview in regular width, re-rendered 400 ms after editing stops
  - hardware keyboard: `.keyboardShortcut` (⌘N invoice, ⇧⌘N quote, ⌘F search, ⌘P print, ⌘↩ issue), `@FocusState` tab order through the builder, `.commands` for the iPadOS menu bar
  - pointer hover and context menus on rows
  - drag and drop: drag the PDF out (`Transferable`), drop an image onto the logo/signature well
  - a PencilKit signature pad (finger on iPhone, Pencil on iPad), AirPrint
- **v1 limits:**
  - **One window** (`UIApplicationSupportsMultipleScenes = NO`), but **fully resizable**. iPadOS 26's windowing makes free resizing the norm (the full-screen opt-out is deprecated), so every layout must work at any width, and state must survive changes between compact and regular width.
- **Why:**
  - Shops often invoice from a counter iPad, and the big screen suits the builder and preview.
  - Once the app is universal, App Review tests it on iPad, so a stretched layout is a rejection risk.
  - SwiftUI makes a properly adaptive app about 8–11 days extra, not a rewrite.
- **Would change my mind:** the iPad work goes past about 12 days. Then fully adapt only the builder, list and preview, and use compact layouts elsewhere.

### D15. iCloud sync (Apple devices only)
- **Options:**
  - (a) Point-Free **SQLiteData**'s sync engine on top of our GRDB database. It is built on Apple's **CKSyncEngine**, which handles scheduling, push-triggered fetches and change tokens.
  - (b) A hand-written CKSyncEngine delegate over GRDB
  - (c) Switch to SwiftData or Core Data with CloudKit
  - (d) A hosted backend (Firebase/Supabase)
- **Choice:** (a).
- **Why:**
  - SQLiteData adds trigger-based change tracking, record mapping, conflict merging, blob-to-CKAsset handling and account-change handling. Written by hand and hard to test, that is about 15–25 days of code, compared with about 6–10 days to integrate SQLiteData.
  - It keeps GRDB migrations and the SQL parity with Room.
  - (c) gives up the explicit schema and migrations, and sync is opaque.
  - (d) is a backend with accounts, which is a v1 non-goal.
  - **Cost:** the Point-Free dependency family, with `@Table` macros on the synced record types. Sync lives in an `InvoiceSync` package behind a `SyncService` protocol, so it can be swapped out.
- **Sync-safe schema rules** (the spec applies them to Android too, so a future cross-platform backend fits):
  - UUID primary keys
  - **no UNIQUE constraints other than the primary key**
  - foreign keys with an explicit `ON DELETE`
  - after 1.0 ships, migrations only add nullable or defaulted columns and tables, and never rename or drop
  - images as BLOB rows, which sync as CKAssets
  - a device-local `device_state` table (device ID, local counter mirror, UI preferences) that is never synced
- **Numbering across devices: device-owned series.**
  - Each `NumberingSeries` has an `owner_device_id`, and only its owner advances it, so offline devices can never produce duplicate numbers.
  - Device 1 owns the default series. The first time device 2 issues an invoice, the user picks its series (default `INV/{fy}/B{seq:4}`, 15 characters, within the Indian limit).
  - A "take over series" action (the user confirms the old device is retired) continues from the highest synced sequence + 1.
  - After every sync, a check flags duplicate numbers, which should be impossible by construction.
- **First launch on a new device:** if an iCloud account exists, the app looks for an existing business in the sync zone *before* onboarding, with a timeout and a "Set up a new business" escape. That prevents duplicate businesses. If duplicates happen anyway, the hidden business picker appears.
- **Conflicts:** SQLiteData's merge policy (per-field last edit wins, to be confirmed in the Phase 0 spike). Payments and line items are separate rows, so most concurrent edits don't collide.
- **Edge cases:**
  - iCloud signed out: local-only, with a banner.
  - **A different Apple ID signs in: pause and ask, never merge two people's data.**
  - Quota full: a banner, and local work continues.
  - Before release, the **CloudKit schema must be deployed to Production** in CloudKit Console (a classic launch-day failure).
- **Privacy:** data sits in the user's *private* iCloud database, which you can't read. Confirm the App Privacy wording in Phase 6.
- **Android:** no sync in v1 (listed in Phase 8).
- **Would change my mind:** the Phase 0 sync spike shows SQLiteData conflicts with our schema, triggers or migrations. Then either hand-write the CKSyncEngine layer (+10–15 days) or ship sync in 1.1, since the schema is already sync-safe.

## 2. Repo structure
```
invoice-app/
├─ CLAUDE.md                  # repo-wide rules: spec-first, fixture-first, parity checklist, commands
├─ Makefile                   # sync-spec, validate-spec, test-core-ios, test-core-android
├─ docs/
│  ├─ decisions/              # ADR-0001-build-order.md … (D1–D13 above)
│  ├─ product/                # PRD, personas, flows, copy, pricing notes
│  ├─ compliance/             # in-gst-invoice-rules.md, uk-vat-invoice-rules.md (sources + "last verified" dates)
│  └─ parity.md               # feature × platform checklist
├─ spec/
│  ├─ README.md               # spec versioning rules
│  ├─ schema/
│  │  ├─ domain.schema.json   # Business, Client, Item, Document, Line, Payment (JSON Schema 2020-12)
│  │  ├─ backup.schema.json
│  │  ├─ tax-config.schema.json
│  │  └─ db/schema.sql + migrations/0001_init.sql …
│  ├─ tax/                    # IN.json, GB.json, GENERIC.json (versioned, effective-dated)
│  ├─ reference/              # currencies.json, countries.json, in-states.json, uqc-units.json
│  ├─ pdf/                    # templates/{classic,modern,minimal,compact}/, render.js, labels/en.json, fonts/, sample-viewmodels/
│  ├─ billing.md              # entitlement state machine, free-limit rules, product IDs
│  ├─ fixtures/               # tax/, numbering/, validation/, words/, format/, backup/, pdf/
│  └─ tools/                  # validate (ajv/check-jsonschema), room-schema-diff, sync script
├─ ios/
│  ├─ CLAUDE.md               # Swift 6, GRDB conventions, how to run tests
│  ├─ InvoiceApp.xcodeproj    # app target only (synchronized folders)
│  ├─ App/                    # @main, AppDependencies, root navigation
│  └─ Packages/
│     ├─ InvoiceCore/         # pure Swift: Money, LocalDate, TaxEngine, Numbering, Validators, Backup codecs
│     ├─ InvoiceData/         # GRDB: migrations, records, repositories
│     ├─ InvoicePDF/          # renderer (per D6) + bundled templates
│     ├─ InvoiceBilling/      # StoreKit 2, EntitlementService
│     ├─ InvoiceSync/         # SQLiteData SyncEngine, device identity, series ownership, account/quota states
│     └─ InvoiceUI/           # design system + feature modules (Profile, Clients, Catalogue, Builder, List, Paywall, Settings)
├─ android/
│  ├─ CLAUDE.md               # Kotlin/Compose conventions, BigDecimal rules, gradle commands
│  ├─ settings.gradle.kts, gradle/libs.versions.toml
│  ├─ app/                    # Application, AppContainer, navigation, feature screens
│  └─ core/{domain,data,pdf,billing,designsystem}/   # 1:1 with the iOS packages
└─ .github/workflows/         # spec.yml, ios.yml (macOS), android.yml (ubuntu); path-filtered
```

## 3. Architecture

### 3.1 Layers (identical on both platforms)
```
UI (SwiftUI / Compose)  →  ViewModel (State + intents)  →  Domain services (IssueDocument, RecordPayment, Backup…)
                                                          →  Repositories (protocol/interface in core, impl in data)
Core (pure, no UI/DB imports): Money · LocalDate · TaxConfig · TaxEngine.compute(draft) → ComputedDocument
                               · NumberFormatter(spec) · AmountInWords · Validators (GSTIN mod-36, UK VAT mod-97) · Backup codec
```
- **The key idea:** `TaxEngine.compute(DocumentDraft, TaxConfig, SellerContext) -> ComputedDocument` is a *pure function*. The builder calls it on every keystroke, the PDF renders only its output, and the fixtures test it exhaustively.
- **Formatting is deterministic.** Money and number formatting for PDFs and the UI uses a small in-house formatter driven by `currencies.json`, covering Indian 3;2 grouping (`₹1,00,000.00`) and standard grouping. Platform ICU versions differ slightly, and PDFs must be identical.

### 3.2 iOS specifics
- **Tooling:** Swift 6 language mode with strict concurrency. View models are `@MainActor`. Core types are `Sendable` structs.
- **Database:** GRDB `DatabasePool` (WAL mode, so reads don't block the write queue). `ValueObservation` → `AsyncSequence` feeds the view models.
- **DI:** `AppDependencies` is created once and injected through `Environment`. Previews and tests use an in-memory database with seeded fixtures.
- **Adaptive UI:** size classes drive the layouts (compact → stacks, regular → split view and two-pane builder). Navigation state lives in routers, not views, so it survives iPad window resizing.
- **Dependencies:** GRDB, SQLiteData (sync only, inside `InvoiceSync`), plus `swift-snapshot-testing` for tests only. QR codes come from CoreImage's `CIQRCodeGenerator`; print/share/save use `UIPrintInteractionController`, `ShareLink`/`UIActivityViewController` and `fileExporter`; preview uses PDFKit `PDFView`.

### 3.3 Android specifics
- **Gradle** (≈ Xcode build system + SPM):
  - Kotlin DSL build files and one version catalog (`libs.versions.toml`, ≈ pinned SPM versions).
  - AGP 9, which has Kotlin support built in, plus the Compose compiler plugin.
  - **KSP**, Kotlin's compile-time code generator (≈ Swift macros), generates Room's DAO code.
- **Modules mirror the iOS packages:**
  - `:core:domain` is a *pure JVM* module with no Android SDK, so its tests run in seconds.
  - `:core:data` holds Room with `exportSchema = true`.
  - Also `:core:pdf`, `:core:billing` and `:core:designsystem` (the Material 3 theme built from shared design tokens).
- **Tablets and foldables (the iPad counterpart):**
  - Apps targeting SDK 36 can no longer lock orientation or resizability on large screens (smallest width ≥ 600 dp), so adaptive layouts are required, not optional.
  - Use **Material 3 Adaptive**: `NavigationSuiteScaffold` switches between bottom bar, navigation rail and drawer by window size (≈ `.sidebarAdaptable`); `ListDetailPaneScaffold` via Navigation 3's list-detail scene (≈ `NavigationSplitView`); `currentWindowAdaptiveInfo()` gives window size classes (≈ size classes).
- **Libraries**, all Jetpack or first-party apart from ZXing:
  - UI: Compose BOM, Material 3, Lifecycle/ViewModel, Navigation 3
  - Data and background: Room, DataStore (typed `UserDefaults`), WorkManager, kotlinx.serialization (≈ `Codable`)
  - Other: Play Billing, and **ZXing core** for QR codes (Android has no built-in QR generator)
  - Tests: JUnit, Turbine, Robolectric, Roborazzi
- **Files:**
  - Sharing a PDF means writing it to the cache folder and exposing it through a **FileProvider**. Android apps can't hand out raw file paths, so other apps get a temporary `content://` URI with a read grant.
  - Sending uses `Intent.ACTION_SEND` with a chooser (≈ `UIActivityViewController`), plus an optional one-tap WhatsApp button that targets the packages `com.whatsapp` / `com.whatsapp.w4b` when installed.
  - Printing uses `PrintManager`. Preview uses `PdfRenderer`, which renders pages to bitmaps, so zooming needs care.

### 3.4 How the two stay consistent
1. **Spec first.** Any behaviour change starts as a spec or fixture change: a PR updates `spec/`, then iOS, then Android is listed in `docs/parity.md`.
2. **Same names.** Modules, types, functions and file names are the same on both sides (`TaxEngine.compute`, `DocumentRepository`, `IssueDocument`). Claude Code can then port file by file with the Swift file as the reference.
3. **Golden fixtures in CI on both platforms.** A spec change triggers both test jobs, and a fixture that isn't implemented on Android is an explicit `@Ignore` listed in `parity.md`.
4. **Schema parity.** One `schema.sql` plus numbered migrations. The Room schema JSON is diffed against it in CI.
5. **One backup format** that both apps read and write, tested with fixture backup files made on the *other* platform.
6. **One set of PDF templates** (if D6 picks A) or one layout spec (if B), with per-template text-extraction fixtures.
7. **The decision log and three `CLAUDE.md` files** carry the rules, so future sessions on either platform follow the same conventions.

## 4. Data model (canonical in `spec/schema/domain.schema.json` + `db/schema.sql`)

**Every table has:**
- `id` TEXT (lowercase UUID)
- `business_id`
- `created_at`, `updated_at` (epoch ms)
- `deleted_at` (a tombstone, i.e. soft delete)

These make multi-business and cross-platform sync later *features*, not migrations. Money is `*_minor INTEGER`; decimals are TEXT. **All synced tables follow the D15 sync-safe rules:** no UNIQUE constraints other than the primary key, additive migrations after 1.0, and images stored as BLOBs. Android's Room schema follows the same rules for parity.

| Entity | Key fields |
|---|---|
| **Business** | Identity and contact: `name`, `legal_name`, `address` (line1, line2, city, `region_code`, postcode, `country_code`), `email`, `phone`, `website`.<br>Tax: `tax_registration` (`regular`, `composition`, `unregistered`, `vatRegistered`, `notRegistered`, all defined by the country config), `tax_id` (GSTIN / VAT no.), `extra_ids` JSON (PAN, UK company no. + registered office, LUT ARN + validity), `home_currency`.<br>Payment: `bank` JSON (account name, number, IFSC / sort code, IBAN, SWIFT), `upi_vpa`, `payment_terms_days`.<br>Defaults: notes, terms, `template_id`, accent colour.<br>Images: `logo_asset`, `signature_asset`. |
| **NumberingSeries** | `doc_type`, `pattern` (e.g. `INV/{fy}/{seq:4}`), `reset` (`never`, `fiscalYear`, `calendarYear`), `next_seq` per `series_key` (the resolved non-sequence part, e.g. FY `25-26`), **`owner_device_id`** (only this device advances the series; see D15), `label` |
| **Client** | `name`, `contact_name`, `email`, `phone`, `billing_address`, `shipping_address`, `country_code`, `region_code` (state), `tax_id`, `is_business` (B2B/B2C), `default_currency`, `notes`, `archived_at` |
| **CatalogItem** | `name`, `description`, `kind` (goods/service), `unit` (UQC code: NOS, HRS, KGS…), `unit_price_minor`, `currency`, `tax_rate_id` (a config reference), `product_code` (HSN/SAC or commodity code), `price_includes_tax`, `archived_at` |
| **Document** | Type and numbering: `doc_type` (`invoice`, `quote`; `creditNote` later), `number` (NULL until issued), `series_key`.<br>Lifecycle: `lifecycle` (`draft`, `issued`, `void`), `issue_date`, `supply_date` (tax point), `due_date` / `valid_until` (quote), `sent_at`, `voided_at` + `void_reason`, `converted_from_id` (quote → invoice), `revision`.<br>Tax setup: `currency`, `exchange_rate` (TEXT, invoice → home currency), `supply_type` (an ID defined by the country config, e.g. IN `domestic` / `exportWithoutTax` / `exportWithTax`; GB `domestic` / `exportServicesB2B` / `exportGoods`; SEZ later), `place_of_supply` (region code), `reverse_charge`, `prices_include_tax`, `tax_config_ref` (e.g. `IN@2025-09-22`).<br>Parties: `client_id` (nullable), `seller_snapshot` JSON, `buyer_snapshot` JSON.<br>Adjustments and text: `discount` (type + value), `shipping_minor` + treatment, `notes`, `terms`, `template_id`.<br>**Stored results:** `subtotal_minor`, `discount_minor`, `tax_minor`, `round_off_minor`, `total_minor`, `computed` JSON (the full `ComputedDocument`). |
| **LineItem** | `document_id`, `position`, `catalog_item_id` (nullable), snapshot fields (`name`, `description`, `product_code`, `unit`), `quantity` TEXT, `unit_price_minor`, `discount` (type + value), `tax_rate_id` + `rate_percent` snapshot, computed `taxable_minor`, `tax_minor`, `total_minor` |
| **TaxLine** | `document_id`, `line_id` (nullable = invoice-level group), `component` (`CGST`, `SGST`, `UTGST`, `IGST`, `VAT`, `CESS`, custom), `rate_percent`, `taxable_minor`, `tax_minor`, `charged` (false under reverse charge). One row per component. This drives the PDF tax table and future GST reports. |
| **Payment** | `document_id`, `amount_minor`, `date`, `method` (cash, bank, UPI, card, cheque, other), `reference`, `note` |
| **AppState** (key/value) | `issued_invoice_count`, `free_limit`, `entitlement` (`free` / `unlocked`, `source`, `transaction_id` / `purchase_token`, `verified_at`), `reminder_defaults`, `last_backup_at`, `schema_version` |
| **Asset** | `mime`, `sha256`, `data` BLOB (logo, signature, downscaled to about 300 KB or less). Kept in the database rather than as loose files, so sync carries them as CKAssets and backups stay a single file. |
| **DeviceState** (local, never synced) | `device_id`, `device_name`, local free-counter mirror, UI preferences, sync status |

**Modelling rules:**
- **Drafts vs issued documents.** Drafts refer to the live client, items and business, and re-snapshot on every save. **Issuing** freezes the snapshots, allocates the number (one transaction, from a series this device owns), stores the `ComputedDocument`, increments the free counter and schedules the reminder.
- **Editing issued documents.** Issued invoices stay editable (with a warning, and `revision` increments) but keep their number. They can never be hard-deleted: "Void" keeps the number and marks the document void. Credit notes come later.
- **Display status is derived** by one core function, `status(doc, payments, today)`:
  - `draft` if not issued
  - `void` if voided
  - `paid` if paid ≥ total
  - `partiallyPaid` if 0 < paid < total
  - `overdue` if today > due date and not paid
  - `sent` if `sent_at` is set
  - `issued` otherwise

  Quotes use `draft`, `sent`, `accepted`, `declined`, `expired`, `converted`. It is covered by fixtures.
- **Converting a quote** copies its lines into a new invoice draft (`converted_from_id`). The quote itself is never changed.
- **Numbering:**
  - **Tokens:** `{prefix}`, `{fy}` (IN: `25-26`), `{yyyy}`, `{yy}`, `{mm}`, `{seq:N}`.
  - **India limits (from config):** at most 16 characters, only `A–Z 0–9 / -`, reset each fiscal year.
  - **Series:** each document type has its own. Quotes use `QT-{seq:4}` and never touch the invoice sequence.
  - **Migrating users:** a user can set the next number once, e.g. to continue from `0142` in another tool.
  - **Multiple devices:** each device issues from its own series (D15). Uniqueness comes from that design and a check after each sync, not from a database index.

## 5. Tax-config schema and engine

### 5.1 Principles
- **Config says *what*; the engine has a small, fixed set of named *how* building blocks.** Examples: the checksum algorithms `gstinMod36` and `ukVatMod97`; the allocation rules `largestRemainder`, `principalSupplyRate` and `apportion`.
- A new country is a JSON file plus fixtures. It needs code only if it requires a new building block, which is added to both platforms together with its fixtures.
- **No general expression language.** Rules match on a fixed set of keys (`supplyType`, `sameRegion`, `sellerRegistration`, `buyerIsBusiness`, `reverseCharge`), all of which must match. That keeps the interpreter small and identical on both platforms.
- **Effective dates.** Rates and configs carry `effectiveFrom`/`effectiveTo`, and the rate is chosen by the document's **supply date**. Issued documents store `tax_config_ref` plus the rate snapshots, so they never change after the fact.
- **Required fields are data.** `requiredFields` per document type drives the builder's warnings ("B2B invoice needs the buyer's GSTIN") and the compliance fixtures.

### 5.2 Shape (abridged `IN.json`; `GB.json` and `GENERIC.json` follow the same schema)
```jsonc
{
  "schemaVersion": 1, "country": "IN", "configVersion": "2025-09-22", "currency": "INR",
  "paperSize": "A4", "fiscalYearStart": "04-01", "numberLocale": "en-IN",
  "labels": { "taxName": "GST", "taxIdName": "GSTIN", "productCodeName": "HSN/SAC" },
  "taxIdFormats": [{ "regex": "^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$",
                     "checksum": "gstinMod36", "regionFromPrefix": 2 }],
  "regions": [ { "code": "29", "name": "Karnataka", "localComponent": "SGST" },
               { "code": "04", "name": "Chandigarh", "localComponent": "UTGST" }, "…all states/UTs; 96 = foreign" ],
  "registrations": [
    { "id": "regular",      "chargesTax": true,  "docTitle": { "invoice": "Tax Invoice" } },
    { "id": "composition",  "chargesTax": false, "docTitle": { "invoice": "Bill of Supply" },
      "mandatoryNotes": ["composition_declaration"] },
    { "id": "unregistered", "chargesTax": false, "docTitle": { "invoice": "Invoice" } } ],
  "rates": [ { "id": "gst_5",  "percent": "5",  "effectiveFrom": "2017-07-01" },
             { "id": "gst_18", "percent": "18", "effectiveFrom": "2017-07-01" },
             { "id": "gst_40", "percent": "40", "effectiveFrom": "2025-09-22" },
             { "id": "gst_12", "percent": "12", "effectiveTo": "2025-09-21" },
             { "id": "exempt", "percent": "0", "category": "exempt" }, "…0, 0.25, 3, nil-rated" ],
  "componentRules": [
    { "when": { "supplyType": "domestic", "sameRegion": true },
      "components": [ { "code": "CGST", "share": "0.5" }, { "code": "$region.localComponent", "share": "0.5" } ] },
    { "when": { "supplyType": "domestic", "sameRegion": false }, "components": [ { "code": "IGST", "share": "1" } ] },
    { "when": { "supplyType": "exportWithoutTax" }, "components": [ { "code": "IGST", "share": "1", "rateOverride": "0" } ],
      "notes": ["export_lut"], "requires": ["seller.extraIds.lutArn", "buyer.country"] },
    { "when": { "supplyType": "exportWithTax" }, "components": [ { "code": "IGST", "share": "1" } ], "notes": ["export_igst_paid"] } ],
  "reverseCharge": { "supported": true, "taxShownButNotCharged": true, "notes": ["rcm"] },
  "rounding": { "taxLevel": "line", "mode": "halfAwayFromZero",
                "grandTotal": { "roundTo": "1", "label": "Round off", "defaultOn": true } },
  "shipping": { "rule": "principalSupplyRate" },
  "productCodes": { "hsnDigits": [ { "maxTurnover": "50000000", "b2b": 4, "b2c": 0 }, { "b2b": 6, "b2c": 6 } ] },
  "numbering": { "maxLength": 16, "allowed": "^[A-Za-z0-9/-]+$", "reset": "fiscalYear", "default": "INV/{fy}/{seq:4}" },
  "foreignCurrency": { "showHomeCurrencyTotals": true },
  "requiredFields": { "invoice.regular": ["seller.taxId", "buyer.taxId?buyerIsBusiness", "placeOfSupply",
                                          "line.productCode", "signature?"] },
  "notesCatalog": {
    "composition_declaration": "Composition taxable person, not eligible to collect tax on supplies",
    "export_lut": "Supply meant for export under Bond or Letter of Undertaking without payment of Integrated Tax",
    "export_igst_paid": "Supply meant for export on payment of Integrated Tax",
    "rcm": "Tax is payable on reverse charge basis" }
}
```
**`GB.json` differences:**
- Registrations `vatRegistered` ("VAT Invoice") and `notRegistered` ("Invoice").
- Rates standard 20 / reduced 5 / zero 0, plus the categories `exempt` and `outsideScope`.
- Rules: `domestic` → `[VAT]`. `exportServicesB2B` → no components + the note "Outside the scope of UK VAT". `exportGoods` → VAT at 0 + a zero-rated note. Reverse charge → the "customer to account for the VAT to HMRC" wording.
- `rounding.taxLevel: "invoice"`, `mode: "towardZero"` (HMRC allows rounding the invoice VAT total down).
- `foreignCurrency.showTaxInHomeCurrency: true`, because VAT totals must also be shown in GBP.
- Numbering doesn't reset.
- All wording and rounding rules are re-checked against VAT Notice 700 in Phase 0.

**`GENERIC.json`:**
- The user defines one or two tax components (name, rate, and optionally `compound: true`).
- `sameRegion` is ignored.
- Numbering is `INV-{seq:4}`.

### 5.3 `TaxEngine.compute` algorithm (the same steps on both platforms, spec'd in `spec/tax/ENGINE.md`)
1. **Resolve context.** Seller registration → `chargesTax` and document title. Supply type. `sameRegion` = seller region (from the GSTIN prefix or profile) == place of supply, which defaults to the buyer's region or `96` for foreign buyers and can be overridden on the invoice.
2. **Per line.** `gross = qty × unitPrice`. Subtract the line discount. **If prices include tax:** `taxable = net × 100 / (100 + Σ component rates)` and `tax = net − taxable`, so the total the user typed is kept exactly.
3. **Invoice-level discount.** Allocated across lines pro rata by taxable value, *before* tax, using largest remainder.
4. **Shipping.** Becomes a pseudo-line whose rate comes from `shipping.rule`: `principalSupplyRate` is the rate of the highest-value line (IN); `apportion` splits it across the lines' rates (GB).
5. **Components.** Pick the first `componentRules` entry that matches, then round tax at `taxLevel`: per line and component, or per rate group. Splitting CGST/SGST uses largest remainder, so CGST + SGST equals the tax at the full rate.
6. **Charged vs shown.** Reverse charge and `exportWithoutTax` show tax lines with `charged:false` (or a 0 rate), and they are left out of the grand total.
7. **Totals.** Round off the grand total if configured. Convert to home currency where required, rounded to home minor units.
8. **Output.** `ComputedDocument`: lines, tax groups, an HSN/rate summary, totals, the resolved `notes[]`, the title, and `warnings[]` for missing required fields.

### 5.4 Fixture format (`spec/fixtures/tax/*.json`)
```jsonc
{ "id": "in-intra-18-inclusive-rounding", "config": "IN@2025-09-22",
  "input":    { "seller": {…}, "buyer": {…}, "draft": {…} },
  "expected": { "title": "Tax Invoice", "taxLines": [ { "component": "CGST", "rate": "9", "taxable": 84746, "tax": 7627 } ],
                "totals": { "taxable": 84746, "tax": 15254, "roundOff": 0, "total": 100000 }, "notes": [], "warnings": [] } }
```
- **Target: at least 80 tax fixtures before Phase 2 is signed off.**
- Every scenario (intra-state / inter-state / UTGST / export under LUT / export with IGST / RCM / composition / unregistered / UK standard, reduced, zero, exempt, outside scope, reverse charge / generic compound) is crossed with inclusive and exclusive prices, discounts, shipping, foreign currency, and negative and .5 rounding boundaries.
- Separate fixture sets cover numbering, GSTIN and VAT validation, amount in words (lakh/crore and million), money formatting and display status.

## 6. PDF templates (after the D6 decision)

**Four templates:**
- **Classic:** bordered GST-style table with per-line tax columns
- **Modern:** accent-colour header band
- **Minimal:** a lot of white space, suited to freelancers
- **Compact:** dense layout for goods with HSN, qty and unit columns

**Every template must support:**
- document titles (Tax Invoice, Bill of Supply, VAT Invoice, Invoice, Quotation)
- CGST/SGST or IGST columns vs a single VAT column
- a tax summary by rate/HSN
- a home-currency equivalents block
- reverse-charge and export wording
- bank details and the UPI QR
- signature plus "Authorised Signatory"
- notes and terms
- page numbers, "continued" markers and a repeated table header

**Fonts:**
- Bundled: Inter/Noto Sans for text, which includes ₹, £ and €.
- Also bundled: a Noto Sans Devanagari fallback, because client names are often typed in Hindi even when the UI is English.

**UPI QR:** encodes `upi://pay?pa=<vpa>&pn=<name>&am=<total>&cu=INR&tn=<invoice no>`. It appears only for INR invoices with a VPA and is hidden once the invoice is paid.

**Sharing:**
- Files are named `<number>-<client>.pdf` and live in a temporary share folder.
- iOS: share sheet, print, save to Files.
- Android: `ACTION_SEND` chooser, a WhatsApp shortcut, `PrintManager`, and SAF "Save as".
- Sharing an issued invoice for the first time asks "Mark as sent?".

## 7. Phases

Effort assumes about 5 dev-days per week. Calendar waits (App Review, beta periods, Play's closed test) are listed separately.

### Phase 0: Foundation, spec and PDF spike
- **Goal:** everything that later phases depend on exists, and the PDF approach is decided using evidence.
- **Tasks:**
  1. **Monorepo and tooling:** Makefile, CI skeleton (spec validation job), root `CLAUDE.md` plus the iOS and Android ones, ADR template, and ADRs for D1–D13.
  2. **Compliance research:** `docs/compliance/` for GST Rule 46 and the Bill of Supply rules, and UK VAT Notice 700 (§16 invoice contents, rounding). Record sources and "last verified" dates. **Book** the CA and accountant reviews.
  3. **Spec v0:**
     - JSON Schemas (domain, backup, tax-config)
     - `IN.json`, `GB.json`, `GENERIC.json`
     - `currencies.json`, `in-states.json`, UQC units
     - `schema.sql` + `0001_init.sql`
     - `spec/tax/ENGINE.md`, `spec/billing.md`
  4. **Fixtures v0:** about 30 tax fixtures (the happy path for each scenario), plus numbering, validators, words and formatting.
  5. **PDF spike (timebox 4 days):** a 1-line invoice, a 60-line invoice, an IGST export invoice and one with Devanagari text in the client name, each rendered through A and B on iOS *and* through A and B on Android (API 26 / 30 / 36, plus one low-end phone), then scored against the D6 rubric → ADR.
  5b. **Sync spike (timebox 2 days):** GRDB migrations + SQLiteData `SyncEngine` on 2 of the draft tables plus an Asset BLOB, run on two devices or simulators on one iCloud account. Check: edits both ways, offline edits on both then merging (see what the conflict policy actually does), delete propagation, account sign-out, and a migration that adds a column. → ADR confirming or rejecting D15(a).
  6. **Design:**
     - low-fi wireframes for the 8 core screens, **each in iPhone and iPad regular-width versions** (the two-pane builder above all)
     - design tokens (colour, type, spacing) in `spec/design/tokens.json`
     - app name + App Store and Play name availability check
  7. **Accounts:**
     - Apple Developer + Paid Apps Agreement and banking, the App Store Connect record, the IAP product in draft
     - **Google Play Console account now.** Identity verification can take days, and a new *personal* account must run a closed test with ≥ 12 testers for 14 consecutive days before production. An *organisation* account needs a D-U-N-S number instead.
     - a privacy-policy page on GitHub Pages
- **Deliverables:** repo, spec v0 passing validation in CI, spike report + ADR, wireframes and tokens, accounts pending or active.
- **Definition of done:**
  - `make validate-spec` passes in CI
  - every D-decision has an ADR
  - the spike ADR has scores and evidence (PDFs committed under `docs/spikes/`)
  - the Play account is created
- **Depends on:** nothing.
- **Risks:**
  - GST/VAT misreadings (mitigation: professional review booked)
  - an inconclusive spike (mitigation: the rubric plus a default of B if still tied)
  - the sync spike failing (mitigation: the D15 fallbacks, with the schema already sync-safe either way)
- **Effort:** 11–14 dev-days.

### Phase 1: iOS data layer, business profile, clients, catalogue
- **Goal:** a user can set up their business and maintain clients and items. Everything is stored in GRDB and survives relaunches.
- **Tasks:**
  - `InvoiceCore` models (Money, LocalDate, value types matching `domain.schema.json`)
  - loading `TaxConfig` from the bundle
  - GSTIN and VAT validators passing their fixtures
  - `InvoiceData`: migrator running `0001`, records, repositories with a protocol per repository, `ValueObservation` streams
  - `AppDependencies`
  - **Onboarding:** country → registration type → business details → tax ID (validated live, and for India the state is read from the GSTIN) → bank/UPI → logo and signature (PhotosPicker, downscaled and stored by content hash)
  - client list, search and editor (B2B/B2C, state picker)
  - catalogue editor (HSN/SAC, unit, rate picker filtered by config and effective date, inclusive-price toggle)
  - settings: numbering series, defaults
  - design system in `InvoiceUI`
  - **Adaptive shell (D14):** `TabView` `.sidebarAdaptable` plus a `NavigationSplitView` list/detail per section. Routers own the navigation state, tested by resizing iPad windows between compact and regular width.
  - **Signature capture** with PencilKit (finger or Pencil), saved as a transparent PNG Asset row. Logos are also Asset rows.
  - `DeviceState` with a generated `device_id`
- **Deliverables:** a TestFlight-internal build with the setup screens, and tests for the repositories and migrations.
- **Definition of done:**
  - CRUD for all three entities
  - validators and config-loading fixtures green
  - in-memory DB tests
  - VoiceOver labels on every control
  - no Swift 6 concurrency warnings
- **Depends on:** Phase 0 spec v0.
- **Risks:**
  - over-building settings (mitigation: only the fields that the configs' `requiredFields` need, plus defaults)
  - image memory use (mitigation: downscale to 1024 px)
  - navigation state lost when size classes change (mitigation: router-owned state plus a resize test)
- **Effort:** 12–15 dev-days.

### Phase 2a: Tax engine and document core, no UI (split out from your Phase 2)
- **Goal:** `TaxEngine.compute`, numbering, status derivation, amount in words and formatting are complete and proven by fixtures.
- **Tasks:**
  - the `round` and `allocate` (largest-remainder) building blocks
  - rule matching and the components logic
  - inclusive-price back-calculation
  - discount allocation and shipping rules
  - reverse charge, export (LUT / IGST), composition, unregistered, GB rules including outside-scope and invoice-level rounding, generic compound tax
  - home-currency conversion
  - `requiredFields` warnings
  - the number allocator (pattern tokens, fiscal-year reset, the IN 16-character limit)
  - `status()` and `AmountInWords` (Indian lakh/crore and international)
  - `IssueDocument` and `ConvertQuote` services, with the transaction wrapped in `InvoiceData`
  - fixtures grown to at least 80, then sent to the CA and the accountant for review
- **Deliverables:** `swift test` all green, the fixture review signed off, and `ENGINE.md` final.
- **Definition of done:**
  - 100% of fixtures pass
  - branch coverage of 90% or more on `TaxEngine`
  - a reviewer's comments resolved or recorded as ADRs
  - config v1 tagged
- **Depends on:** Phase 1 models.
- **Risks:**
  - **the biggest correctness risk in the project** (mitigation: fixtures first, then the professional review)
  - rounding edge cases (mitigation: dedicated rounding fixtures)
  - scope growth from the four extra scenarios (mitigation: SEZ, cess and TDS stay out of v1)
- **Effort:** 9–12 dev-days.

### Phase 2b: Document builder UI (invoices and quotes)
- **Goal:** create, edit and issue invoices and quotes quickly on a phone, with live totals.
- **Tasks:**
  - **Builder screen:**
    - client picker (+ quick-add), document type toggle, dates (issue / supply / due, payment-terms presets)
    - supply type and place of supply (shown only when relevant)
    - reverse-charge toggle (when the config supports it), inclusive-price toggle, currency and exchange rate
  - **Lines:**
    - add from the catalogue (search) or a one-off line; qty, unit, price, discount, rate
    - swipe to delete, drag to reorder, duplicate a line
  - **Charges and totals:** invoice discount, shipping, a live totals card with the tax breakdown, notes and terms
  - **Warnings and actions:**
    - a warnings banner driven by `warnings[]`
    - autosave drafts (500 ms debounce)
    - "Issue" (confirm → number allocated), "Duplicate invoice", "Convert quote → invoice"
  - keyboard toolbar, decimal-pad handling per locale, Dynamic Type layout checks
  - **iPad:**
    - a two-pane builder (form + live PDF preview; until Phase 3 exists, a totals and tax panel is the placeholder)
    - hardware-keyboard shortcuts and `@FocusState` tab order through line fields (⌘↩ issue, ⌘D duplicate line)
    - a line editor that uses popovers in regular width
- **Deliverables:** a builder that works end to end with issued documents saved.
- **Definition of done:**
  - a 5-line GST invoice issued in under 60 s by a new user in hallway testing
  - view model tests for the builder intents
  - no totals differing from the engine output
  - drafts survive the app being killed
- **Depends on:** 2a.
- **Risks:**
  - form complexity (mitigation: progressive disclosure, so export, RCM and currency sit under an "Advanced" section)
  - decimal input bugs (mitigation: parse with the spec parser, never `Double`)
- **Effort:** 13–17 dev-days.

### Phase 3: PDF generation, templates, UPI QR, sharing
- **Goal:** professional, compliant PDFs from any document, previewed and shared in two taps.
- **Tasks:**
  - the PDF view-model builder (`ComputedDocument` + snapshots → formatted strings and labels from `spec/pdf/labels/en.json`)
  - the renderer chosen by the spike, and the four templates with an accent colour
  - pagination rules, fonts, UPI QR
  - a preview screen (PDFKit) with a template switcher
  - share, print, save to Files, and the "Mark as sent?" prompt
  - PDF caching by document revision
  - **iPad:**
    - the preview renders in the builder's right pane (debounced, off the main thread where the renderer allows)
    - drag the PDF out to Mail/Files (`Transferable`), ⌘P print
  - text-extraction and snapshot tests per template
  - **a friends-and-family TestFlight** with 5–10 real UK and Indian small businesses to validate the templates early
- **Deliverables:** four templates × all document types; the TestFlight feedback log.
- **Definition of done:**
  - every PDF fixture's text expectations pass
  - the 60-line invoice paginates correctly
  - generation takes 1 s or less on an iPhone XR-class device
  - the CA and accountant confirm a sample GST invoice, Bill of Supply, export invoice and VAT invoice each meet the mandatory-field rules
- **Depends on:** 2a (outputs), 2b (documents to render), the Phase 0 spike.
- **Risks:**
  - edge cases in WebKit pagination (mitigation: CSS `break-inside: avoid`, a totals block of fixed height)
  - template taste (mitigation: early feedback from TestFlight users)
  - live-preview rendering cost (mitigation: debounce, cancel stale renders, render only page 1 while typing)
- **Effort:** 11–14 dev-days.

### Phase 4: Status tracking, list and dashboard, reminders, backup and restore
- **Goal:** users can see what they're owed, record payments, get reminded, and never lose data.
- **Tasks:**
  - **Payments:** record a payment (partial or full, method, reference), with derived status chips.
  - **Lists and dashboard:**
    - list with segments (All / Unpaid / Overdue / Paid / Drafts / Quotes), search (client, number) and date filters
    - client detail with its documents and outstanding balance
    - dashboard: outstanding, overdue and paid this month, all in home currency and computed with SQL `SUM`
  - **Document actions:** void with a reason, and the quote lifecycle (accepted/declined/expired).
  - **Reminders:**
    - business default "remind N days after due", overridable per invoice
    - local notification scheduling and a reschedule-on-launch reconciler
    - a "Send reminder" action pre-filling a WhatsApp or email message (amount, due date, UPI link) with the PDF attached
  - **Backup and restore:**
    - export `.invoicebackup` via share sheet or `fileExporter`
    - restore via `fileImporter`: validate → preview counts → take a safety snapshot → replace all → rebuild the reminders
    - a "Last backup: N days ago" nudge in Settings
  - **iPad:**
    - list/detail with the document preview in the detail column
    - row context menus (duplicate, record payment, share, void), ⌘F search
    - drop a `.invoicebackup` file onto Settings to restore
- **Deliverables:** a complete invoicing loop, plus backup fixtures committed to `spec/fixtures/backup/`.
- **Definition of done:**
  - status fixtures pass
  - a backup round trip is lossless: export → wipe → restore → the same database hash, assets included
  - a restore of a corrupted file fails safely with no data change
  - reminders appear after the due date on a device test
- **Depends on:** Phase 3 (reminders attach the PDF).
- **Risks:**
  - the 64-notification cap on iOS (mitigation: schedule the nearest 50 and reconcile on launch)
  - large backups because of logos (mitigation: downscaling in Phase 1)
- **Effort:** 11–14 dev-days.

### Phase 4b: iCloud sync between iPhone and iPad (new)
- **Goal:** the same Apple ID sees the same business, clients, items, documents and payments on every iPhone and iPad within seconds when online. No duplicate numbers and no lost rows after working offline.
- **Why here:** the schema is nearly final after Phase 4 (sync makes later schema changes additive-only), and this comes before the paywall so the cross-device free-limit logic is built once.
- **Tasks:**
  - **`InvoiceSync`:**
    - `SyncEngine` over all business tables (`DeviceState` excluded), behind the `SyncService` protocol
    - capabilities: iCloud/CloudKit container, Push Notifications, Background Modes → remote notifications (CloudKit wakes the app with silent pushes)
  - **Numbering:** device-owned series (owner assignment, a series picker on the second device's first issue, "take over series", the duplicate check after sync) from D15.
  - **First launch:** an iCloud check before onboarding (10 s timeout + skip), and the hidden duplicate-business picker.
  - **Settings:** a sync status row ("Up to date / Syncing / Paused: signed out / iCloud storage full") and a sync on/off toggle that keeps local data.
  - **Edge cases:**
    - an account change pauses sync and asks the user
    - quota errors show a banner
    - restore-with-sync semantics (D13)
  - **Reconcilers after each sync:**
    - local reminders are rescheduled or cancelled for invoices issued or paid on another device
    - the PDF cache is invalidated by `revision`
    - the cross-device free-limit check (D8)
  - **Tests:** unit tests for series ownership and the duplicate check, and a `SyncService` fake in the view-model tests.
- **Deliverables:** sync between iPhone and iPad on TestFlight, and the D15 ADR updated with the conflict behaviour actually observed.
- **Definition of done** (the two-device script in §11 passes):
  - edits made online reach the other device in under 30 s
  - concurrent offline edits merge with no lost rows
  - deletes propagate
  - two devices issuing offline never produce the same number
  - switching Apple ID pauses sync
  - a restore warns, then propagates
  - no sync work on the main thread
- **Depends on:** Phases 1–4, and the Phase 0 sync spike.
- **Risks:**
  - duplicate businesses on first launch (mitigation: the check before onboarding, plus the picker)
  - surprise conflicts on issued documents (mitigation: those edits are rare; an "edited on another device" banner driven by `revision`)
  - schema changes after 1.0 (mitigation: the additive-only rule in `CLAUDE.md` and migration review)
  - the dependency itself (mitigation: `SyncService` isolation)
- **Effort:** 12–16 dev-days.

### Phase 5: Paywall, free-invoice counter, StoreKit 2
- **Goal:** monetisation that is fair, can be restored, and passes review.
- **Tasks:**
  - `InvoiceBilling` implementing the `spec/billing.md` state machine
  - a `.storekit` configuration file for local and unit testing (`SKTestSession`)
  - a counter hooked into `IssueDocument`, mirrored to the Keychain, and checked across synced devices (D8)
  - **Paywall:** shown when the user taps Issue at the limit, and from Settings. It shows the localised price from `Product.displayPrice`, restores purchases, and handles pending Ask to Buy.
  - the unlocked state across the app
  - refund and revocation handling
  - sandbox testing on a device
  - set UK and India prices manually in App Store Connect
- **Deliverables:** purchase, restore and revoke all working in sandbox, and the IAP submitted with its review screenshot.
- **Definition of done:**
  - unit tests for every state transition
  - the manual sandbox matrix (buy / cancel / Ask to Buy / restore on a second device / refund via StoreKit test) passes
  - existing documents stay accessible when locked
- **Depends on:** Phase 2a (`IssueDocument`).
- **Risks:**
  - review rejection for a missing restore option or unclear pricing (mitigation: a checklist based on guideline 3.1.1)
  - the counter reset by reinstalling (accepted, since the Keychain mirror is best effort)
- **Effort:** 4–6 dev-days.

### Phase 6: iOS polish, release readiness, beta, App Store launch
- **Goal:** a 1.0 you'd be proud of in UK and Indian storefronts.
- **Tasks:**
  - **Accessibility:** Dynamic Type up to XXL, VoiceOver, 4.5:1 contrast, Reduce Motion.
  - **Localisation:** a String Catalog in English, with en-GB/en-IN variants such as "Postcode" vs "PIN code" and "VAT" vs "GST". Pseudo-locale testing so Hindi is cheap later.
  - **Craft:** empty states, onboarding sample data ("Try with a demo invoice"), haptics, app icon, launch screen.
  - **Diagnostics:** MetricKit handler plus Organizer review. The Sentry decision gate from D11 happens here.
  - **Performance:** 1,000 invoices seeded → the list scrolls at 60 fps and search returns in under 100 ms.
  - **Beta:** external TestFlight (Beta App Review) with 20–50 users, **at least 5 of them using both an iPhone and an iPad** to exercise sync, for 2–3 weeks; then triage and a fix sprint.
  - **iPad QA matrix:**
    - iPad mini portrait
    - iPad Pro 13" with keyboard and trackpad
    - every window size from compact to full, and the resizable iPadOS 26 windows
    - keyboard-only builder flow, pointer and context menus, drag and drop
  - **Sync release checklist:**
    - **deploy the CloudKit schema to Production** in CloudKit Console, then test a TestFlight build against Production
    - confirm the App Privacy wording for data kept in the user's private iCloud
  - **Mac gate (1 day):** run it as "Designed for iPad" on an Apple silicon Mac (sync, printing, file export, keyboard). If it behaves well, switch Mac availability on in App Store Connect; otherwise leave it off and log the issues for Phase 8.
  - **Store listing:**
    - screenshots for 6.9" iPhone and **13" iPad**, which highlight the two-pane builder
    - description and keywords per storefront
    - the privacy label ("Data Not Collected", subject to the iCloud wording check above), the privacy policy URL, age rating
  - **Release:** phased release over 7 days. Ship to all storefronts or only GB + IN (recommended: all, with the GENERIC config).
- **Deliverables:** App Store 1.0 live, and a post-launch monitoring checklist.
- **Definition of done:**
  - zero open P0/P1 bugs
  - crash-free sessions of 99.5% or more in the beta
  - an accessibility audit checklist complete
  - the release ADR written, recording what was learned for the Android port
- **Depends on:** Phases 1–5.
- **Risks:**
  - App Review delays (mitigation: submit the IAP together with the app, and budget a week)
  - beta feedback that forces spec changes (mitigation: that's the point, since the spec is updated *before* Android starts)
- **Effort:** 12–16 dev-days + 3–5 weeks elapsed (beta + review). **Phase 7a can start during the beta wait.**

### Phase 7a: Android setup, core port, data layer, setup screens
- **Goal:** the Android project is set up, `:core:domain` passes *every* fixture that iOS passes, and setup screens and data match iOS Phase 1.
- **Tasks:**
  1. **Ramp-up (2–3 days, deliberately budgeted):**
     - Kotlin basics for Swift developers: `val`/`var`; `data class` (a *reference* type with value equality, changed via `copy()`, unlike a Swift struct); null safety (≈ optionals); `sealed interface` (≈ an enum with associated values); extension functions.
     - Coroutines: `suspend` ≈ `async`; `Flow` ≈ `AsyncSequence`; `StateFlow` ≈ an observable current value; `viewModelScope` ≈ a task tied to the view model; `Dispatchers.IO` ≈ a background executor.
     - The official "Compose for SwiftUI developers" material.
  2. **Project:**
     - Android Studio (≈ Xcode) project, Gradle Kotlin DSL, `libs.versions.toml`
     - build types `debug`/`release` (≈ build configurations)
     - `applicationIdSuffix ".debug"` so debug and release builds can be installed side by side
     - ktlint + Android Lint (≈ SwiftLint), and the CI job on Ubuntu
  3. **`:core:domain`:**
     - Port `InvoiceCore` file by file with Claude Code, with the Swift file and the fixtures as the reference.
     - `BigDecimal` rules from D7.
     - kotlinx.serialization for configs and fixtures.
     - A JUnit parameterised runner over `spec/fixtures/**`.
     - The same fixture count must pass as on iOS.
  4. **`:core:data`:**
     - Room entities and DAOs matching `schema.sql` (with `Flow` return types)
     - migrations mirroring GRDB's, the exported schema, the CI schema diff
     - repositories and the `AppContainer`
  5. **Setup screens:** onboarding, business profile (Photo Picker, which needs no storage permission), clients, catalogue, settings.
     - An adaptive shell with `NavigationSuiteScaffold` and list-detail panes (the D14 counterpart).
     - A signature pad: Compose `Canvas` + `pointerInput` → path → PNG Asset row. That is about a day, compared with PencilKit on iOS.
     - The UI uses Material 3 styled with the shared tokens. Don't copy iOS navigation patterns: use a top app bar, a floating action button and system back.
     - Handle edge-to-edge insets and the predictive-back gesture.
  6. **First upload:** a first internal-track upload so the billing product can be created.
- **Deliverables:** a Play internal-testing build with the setup flows, and `:core:domain` green on all fixtures.
- **Definition of done:**
  - fixture parity at 100%
  - Room migration tests pass
  - survives rotation, dark mode and "Don't keep activities" (a developer option that simulates process death) with no data loss
- **Depends on:** iOS Phase 2a (the complete core) and Phase 6 spec updates, so ideally start after the iOS beta feedback is folded into the spec.
- **Risks:**
  - the learning curve (mitigation: budgeted ramp-up and a detailed `android/CLAUDE.md`)
  - Gradle and AGP version churn (mitigation: pin versions and use the Android Studio upgrade assistant)
- **Effort:** 13–18 dev-days.

### Phase 7b: Android builder, tax engine in the UI, PDF, lifecycle features
- **Goal:** feature parity with iOS 1.0 except billing.
- **Tasks:**
  - builder (invoices and quotes) with view models mirroring iOS state and intents, `SavedStateHandle` for the draft ID, autosave to Room
  - **PDF:** the renderer from the D6 decision running the *same* templates, so the spike's Android code becomes production code. Preview uses `PdfRenderer` in a `LazyColumn` with pinch-zoom.
  - sharing via FileProvider plus a chooser and the WhatsApp shortcut, `PrintManager`, SAF save
  - UPI QR with ZXing
  - payments, list and dashboard
  - reminders: a daily `PeriodicWorkRequest` through WorkManager, the `POST_NOTIFICATIONS` prompt at the point it's needed, a notification channel ("Payment reminders"). Notification channels are an Android concept: every notification category the user can mute separately in system settings.
  - **Backup:** the SAF `CreateDocument` / `OpenDocument` contracts. **Restoring a backup made on iOS must pass.**
  - **Auto Backup:** `dataExtractionRules` include the DB and assets and exclude the caches.
  - **Screenshot tests:** Roborazzi per template and screen, at compact, medium and expanded widths.
  - **Large screens:**
    - two-pane builder with live preview at expanded width
    - list/detail for documents and clients
    - hardware-keyboard shortcuts (`Modifier.onKeyEvent`, Ctrl+N)
    - resizing tested in freeform windows and on a foldable emulator (folded/unfolded)
  - **No sync on Android in v1:** the sync-safe columns exist but are unused. Moving data between Android devices or across platforms is done through backup/restore.
- **Deliverables:** an internal build at parity, and `docs/parity.md` all ticked except billing.
- **Definition of done:**
  - PDF text-extraction fixtures pass
  - cross-platform backup round trips in both directions
  - generation takes 2 s or less on the low-end test device
  - no ANRs in a 30-minute monkey test (`adb shell monkey`, a random-input stress tool)
- **Depends on:** 7a.
- **Risks:**
  - WebView PDF quirks across Android versions and OEMs (mitigation: the spike device matrix and Firebase Test Lab smoke runs, a cloud device farm similar to running XCUITests on real devices)
  - OEM background limits for reminders (mitigation: documented as best effort, with an in-app "Overdue" badge as the reliable fallback)
- **Effort:** 18–24 dev-days.

### Phase 7c: Play Billing, testing tracks, release
- **Goal:** Android 1.0 in production with fair monetisation.
- **Tasks:**
  - `:core:billing` implementing the same state machine:
    - `BillingClient` with pending purchases and automatic reconnection
    - `queryPurchasesAsync` on start and resume
    - **acknowledge within 3 days**
    - unlock only on `PURCHASED`; handle `PENDING` UPI/cash purchases in the UI
  - the free-tier counter mirrored to Block Store (best effort)
  - billing tests with license testers
  - **Release engineering:**
    - R8 code shrinking/obfuscation (no iOS equivalent) with keep rules for kotlinx.serialization
    - upload the R8 mapping file (≈ dSYMs) so crash stack traces are readable
    - **Baseline Profile**: a list of hot code paths that Android compiles ahead of time on install, giving faster startup and less jank on low-end phones (iOS doesn't need it, because Swift is always compiled ahead of time)
  - **Signing:** Play App Signing, where Google holds the app signing key and you keep an *upload key*. Back up the upload keystore; a lost one can be reset through Play support, but it is slow.
  - **Play Console:** Data safety form, content rating questionnaire (IARC), target audience, the **financial features declaration** ("no financial services"), store listing, phone **and 7"/10" tablet screenshots**, and a pass through Google's large-screen app quality checklist.
  - **Tracks:** internal (≈ internal TestFlight, instant) → **closed test (≥ 12 testers for 14 days if the account is personal; start this at the beginning of 7b so it overlaps)** → production with a staged rollout at 10% → 50% → 100% (≈ phased release, but you control the percentages and can halt it).
- **Deliverables:** Play production 1.0.
- **Definition of done:**
  - purchase, cancel, pending → complete, and reinstall-restore all verified
  - Android vitals crash rate under 1% and ANR rate under 0.47% (Play's "bad behaviour" thresholds) during the rollout
- **Depends on:** 7b; the closed-test clock started earlier.
- **Risks:**
  - the 14-day closed-test gate (mitigation: recruit testers during iOS beta, among the Indian TestFlight users' Android-using peers)
  - forgetting to acknowledge purchases (mitigation: a unit test plus a startup sweep that acknowledges any unacknowledged `PURCHASED` purchase)
- **Effort:** 8–10 dev-days + about 3 weeks elapsed (partly overlapping).

### iOS → Android glossary (for Phase 7)
| iOS | Android | Note |
|---|---|---|
| Xcode, Simulator | Android Studio, Emulator (AVD) | The emulator is a full system image; test on at least one real low-end phone |
| SPM `Package.swift`, local packages | Gradle modules, `libs.versions.toml` | Gradle builds are programmable scripts, not a declarative manifest |
| Schemes / build configurations | Build types (+ product flavours) | Flavours ≈ separate targets sharing code; not needed in v1 |
| Swift macros | KSP (code generation) | Room generates DAO code with KSP |
| SwiftUI `View`, `@State` | `@Composable`, `remember` / `rememberSaveable` | "Recomposition" ≈ body re-evaluation; keep composables pure |
| `@Observable` view model | `ViewModel` + `StateFlow` | The `ViewModel` survives configuration changes; state lost to process death is restored from `SavedStateHandle` |
| `NavigationStack(path:)` | Navigation 3 back stack | Both are lists of route values that you own |
| `NavigationSplitView` | `ListDetailPaneScaffold` (Material 3 Adaptive + the Nav3 list-detail scene) | |
| `TabView` `.sidebarAdaptable` | `NavigationSuiteScaffold` | Bottom bar ↔ rail ↔ drawer by window size |
| Size classes | Window size classes (`currentWindowAdaptiveInfo()`) | Compact / medium / expanded widths |
| PencilKit | Compose `Canvas` + `pointerInput` | Android has no built-in ink/signature view |
| `.keyboardShortcut`, `.commands` | `Modifier.onKeyEvent` (+ `onProvideKeyboardShortcuts`) | Matters on tablets and Chromebooks |
| CloudKit / CKSyncEngine | Nothing equivalent built in | Android v1 has no sync; a hosted backend comes later |
| `Environment` DI | Manual `AppContainer` (later Hilt) | |
| GRDB, `ValueObservation` | Room, `Flow` from DAOs | Same SQLite schema |
| `UserDefaults` | DataStore (Preferences) | Async and transactional |
| Keychain | Keystore / Block Store | Nothing on Android survives an uninstall by default |
| `BGTaskScheduler` / local notifications | WorkManager + `NotificationManager` + channels | Android background work is dependable, except on some OEMs |
| `UIActivityViewController` / `ShareLink` | `Intent.ACTION_SEND` + FileProvider | Share `content://` URIs, never file paths |
| `fileExporter` / `fileImporter` | SAF `CreateDocument` / `OpenDocument` | No storage permission needed |
| `UIGraphicsPDFRenderer`, PDFKit | `PdfDocument` / `WebView` print, `PdfRenderer` | Preview renders to bitmaps |
| StoreKit 2 | Play Billing Library | Acknowledge within 3 days; pending purchases |
| TestFlight internal / external | Internal / closed / open tracks | New personal accounts: 14-day closed-test rule |
| Phased release | Staged rollout (%) | Can be halted or resumed |
| dSYMs, Organizer, MetricKit | R8 mapping, Android vitals | |
| XCTest / Swift Testing | JUnit (+ Robolectric, Turbine) | JVM tests run without an emulator |
| XCUITest | Compose UI tests / Espresso | |
| swift-snapshot-testing | Roborazzi | |
| SwiftLint / swift-format | ktlint / Detekt / Android Lint | |

### Phase 8: Post-launch, driven by feedback
- **Goal:** grow on evidence, one release every 2–4 weeks, alternating platforms or shipping together through the spec.
- **Candidate backlog, in suggested order** (each is a spec + fixtures + two implementations):
  1. **Credit notes** (the model is ready: `doc_type=creditNote`, a negative-total fixture, a reference to the original invoice).
  2. **CSV export for accountants**, including a GSTR-1-friendly HSN summary and a UK VAT summary by rate.
  3. **Recurring invoices** (templates plus schedules; issuing on Android via WorkManager, on iOS via notifications that prompt the user to issue).
  4. **Reports** (SQL aggregates: sales by month, client, tax rate).
  5. **Hindi UI** (the String Catalog and `strings.xml` are already structured for it).
  6. **Tax-config updates over the air**: a signed JSON on a static host, verified with a bundled public key. That is still no backend, and rate changes stop needing an app release.
  7. **Multi-business.**
  8. **Cross-platform sync (Android ↔ Apple).** iCloud covers Apple devices from v1. Android needs a hosted backend (Supabase, Firebase or your own), with an ADR covering cost, a sync *subscription* to fund it, and whether iOS moves off CloudKit or bridges both. The sync-safe schema is already there.
  9. **Shop features:** thermal receipt printing (ESC/POS over Bluetooth), barcode item lookup, a bundled HSN/SAC search.
  10. **Platform extras:** App Intents / Shortcuts ("Invoice Acme for 3 hours"), widgets (outstanding total), Android app shortcuts.
  11. **Multiple iPad windows** (a client and an invoice side by side), and **Mac Catalyst** if "Designed for iPad" falls short at the Phase 6 gate.
  12. **CloudKit sharing (CKShare):** share a business with a partner or accountant (Apple-only). SQLiteData supports it.
- **Definition of done per item:** the ADR exists if it's architectural, fixtures are green on both platforms, and `parity.md` is updated.

## 8. Effort summary (solo developer with Claude Code, 1 dev-day ≈ 6 focused hours)
| Phase | Dev-days | Elapsed extras |
|---|---|---|
| 0 Foundation, spec, PDF and sync spikes | 11–14 | Account verification (days) |
| 1 iOS data, setup, adaptive shell | 12–15 | |
| 2a Tax engine core | 9–12 | Professional review (about 1 week, in parallel with 2b) |
| 2b Builder UI (iPhone + iPad two-pane) | 13–17 | |
| 3 PDF and sharing | 11–14 | Friends-and-family TestFlight |
| 4 Status, reminders, backup | 11–14 | |
| 4b iCloud sync | 12–16 | |
| 5 StoreKit 2 | 4–6 | |
| 6 Polish, iPad QA, launch | 12–16 | 3–5 weeks of beta + review (7a runs in parallel) |
| **iOS/iPadOS total** | **95–124** (≈ 19–25 weeks full-time) | |
| 7a Android setup and data | 13–18 | |
| 7b Android parity + large screens | 18–24 | Closed test starts here (14 days) |
| 7c Play Billing and launch | 8–10 | Staged rollout |
| **Android total** | **39–52** (≈ 8–10.5 weeks) | |
| **Both stores** | **≈ 134–176** (≈ 6.5–8.5 months full-time) | |

**Where the growth came from:**
- The tax, quote, UPI and reminder additions: about 12–16 days.
- iPad plus Android large screens: about 12–16 days.
- iCloud sync including its spike: about 14–18 days.

If the date matters more than scope, **moving Phase 4b to 1.1** is the cleanest cut (about −14 days on the iOS critical path, with no structural cost). Part-time (about 20 h/week), multiply the calendar time by about 1.8.

## 9. Cross-cutting risk register
| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| Tax rules wrong or changed (e.g. GST 2.0) | Med / High | Fixtures first, professional review, effective-dated configs, frozen snapshots, over-the-air config later |
| Android WebView PDF fragility | Med / High | Spike with a device matrix; option B as the fallback; renderer isolated behind an interface |
| Scope creep (v1 is already bigger than the brief) | High / Med | Phase gates; the "later" list stays later; the parity doc is the scope contract |
| Data loss (migrations, restore, uninstall) | Low / Critical | Migration tests, safety snapshots, backup nudges, issued documents never hard-deleted |
| Weak unit economics at £1 | High / Med | Price is set in the stores; free tier counts only issued invoices; revisit after 30 days of data |
| Store gates (review 3.1.1, closed test, financial declaration) | Med / Med | Checklists in Phases 5, 6 and 7c; closed test started early |
| Learning Android while shipping | Med / Med | Ramp-up budget, glossary, fixtures as the answer key, `android/CLAUDE.md` |
| SDK churn (iOS 27 / Android 17, AGP) | Med / Low | Pinned toolchains; upgrades in their own PRs |
| Sync data problems (duplicates, conflicts, account switches) | Med / High | Phase 0 spike, device-owned series, iCloud check before onboarding, two-device script, `SyncService` isolation |
| CloudKit schema not deployed to Production | Low / Critical | A Phase 6 checklist item and a TestFlight test against Production |
| iPad layouts breaking at odd window sizes | Med / Med | Router-owned navigation state, resize tests, the iPad QA matrix |
| Schedule growth from adding iPad and sync | High / Med | The biggest lever is moving Phase 4b to 1.1. The schema is sync-safe from day one, so deferring costs nothing structurally. |

## 10. What the `CLAUDE.md` files will enforce
- **Root:**
  1. Spec first: behaviour changes start in `spec/` with fixtures.
  2. Never `Double`/`Float` for money, rates or quantities. Round only through the core `round()`.
  3. Lowercase UUIDs, calendar dates as `LocalDate`, timestamps in epoch ms UTC.
  4. Issued documents are never renumbered or hard-deleted, and numbers only come from a series this device owns. Sync-safe schema: no UNIQUE constraints except primary keys, and migrations are additive only after 1.0.
  5. The same type and module names on both platforms. Update `docs/parity.md`.
  6. Run `make test-core-ios` / `make test-core-android` before committing. ADR for any D-level change.
- **`ios/CLAUDE.md`:** Swift 6 strict concurrency; GRDB patterns (records, migrations, observation); view-model conventions; adaptive-layout rules (every screen works from compact to regular width, and navigation state lives in routers); sync rules (`DeviceState` is never synced); how to run `swift test` and `xcodebuild`.
- **`android/CLAUDE.md`:**
  - `BigDecimal` rules; coroutine and `Flow` conventions
  - `rememberSaveable` vs view-model state; process-death checklist
  - Gradle commands; "port from the Swift file X, keep names"

## 11. Verification (how each milestone is proven)
- **Spec:** `make validate-spec` checks every config and fixture against the JSON Schemas; `make sync-spec --check` confirms the bundled copies are up to date.
- **iOS core and app:**
  - `swift test --package-path ios/Packages/InvoiceCore` (every fixture)
  - `xcodebuild test -scheme InvoiceApp -destination 'platform=iOS Simulator,name=<current iPhone>'` (data, view models, PDF snapshots, UI smoke)
- **Android core and app:**
  - `./gradlew :core:domain:test` (same fixtures, same count)
  - `./gradlew testDebugUnitTest lint` (Room migrations, view models, Roborazzi)
  - `./gradlew connectedDebugAndroidTest` on an emulator for instrumented migration and UI smoke tests
  - `spec/tools/room-schema-diff` in CI
- **Cross-platform:**
  - a backup exported by iOS is restored in the Android test suite, and the reverse
  - PDF text-extraction fixtures pass on both platforms
  - `parity.md` has no unticked v1 rows
- **Manual acceptance script** (every release, both platforms):
  1. Set up a regular GST business in Karnataka.
  2. Add a client in Maharashtra, so the invoice should show IGST.
  3. Create a 3-line tax-inclusive invoice with a discount and shipping, and issue it.
  4. Preview it in each template and share it to WhatsApp.
  5. Record a partial payment.
  6. Move the device date past the due date and check the reminder and the overdue status.
  7. Repeat for a UK VAT-registered business: one reverse-charge invoice and one to an overseas client.
  8. Convert a quote to an invoice.
  9. Back up, delete the app, reinstall and restore.
  10. Hit the free limit, buy in sandbox or as a license tester, then restore on a second device.
- **iPad:**
  - the UI smoke tests also run on an iPad simulator (`-destination 'platform=iOS Simulator,name=<current iPad Pro 13-inch>'`)
  - snapshot tests of each main screen at compact and regular width
  - a manual resize pass through the iPadOS 26 window sizes
- **Android large screens:** the Compose UI smoke tests on a tablet emulator and a foldable emulator (folded and unfolded), and Roborazzi snapshots at the three width classes.
- **Two-device sync script** (iPhone + iPad on one Apple ID; before release, a TestFlight build against the CloudKit **Production** environment):
  1. Create a client on the iPhone. It should appear on the iPad in under 30 s.
  2. Turn on airplane mode on both. Edit different fields of the same draft on each device and issue one invoice on each. Reconnect: both edits should merge, and the numbers should come from different series.
  3. Delete a catalogue item on the iPad. It should disappear on the iPhone.
  4. Record a payment on the iPhone. The iPad's reminder for that invoice should be cancelled.
  5. Sign the iPad into a different Apple ID. Sync should pause and ask, with no data mixed.
  6. Restore a backup on the iPhone with sync on. The warning should appear, and the iPad should end up with the same data.
- **Compliance:** CA and UK accountant sign-off on the fixture set (Phase 2a) and on sample PDFs (Phase 3), recorded in `docs/compliance/`.

## 12. First steps after approval
Phase 0, tasks 1 → 3 → 4, in that order: repo skeleton and `CLAUDE.md` files, then spec v0, then fixtures v0. The PDF spike (task 5) follows once a sample `ComputedDocument` exists to render, and the sync spike (task 5b) once `schema.sql` v0 exists. Accounts (task 7) start on day one because they involve waiting.
