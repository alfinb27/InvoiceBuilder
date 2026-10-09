# Android app rules

Read the root `CLAUDE.md` first. The Android app is a port of the iOS app (Phase 7): **port from the Swift
file, keep the names**, and prove behaviour with the same `spec/fixtures`. The developer is an experienced
iOS engineer, so explanations and code comments should map Android concepts to their iOS equivalents.

## Stack

- Kotlin 2.x (K2), Jetpack Compose + Material 3 (+ Material 3 Adaptive), minSdk 26, target/compile SDK 37
  (the Compose BOM requires 37; ADR-0018).
- Gradle Kotlin DSL, one version catalog (`gradle/libs.versions.toml` ≈ pinned SPM versions), AGP 9, KSP
  (compile-time code generation ≈ Swift macros).
- **As iOS (ADR-0018):** routers (`AppRouter`, `DocumentsRouter`, …) and screen models hold Compose snapshot state
  (`mutableStateOf` ≈ `@Observable`); the `Session` owns them and the activity-scoped `AppModel` (an
  `AndroidViewModel`) owns the session, so rotation and folding keep everything. Open editors live in
  `Session.retained(key)` and are released when they close. Room `Flow`s are collected with
  `collectAsStateWithLifecycle`. Manual DI via `AppContainer` in `InvoiceApplication` (≈ `AppDependencies`).
- Room (SQLite, same schema as GRDB), WorkManager (daily reminders job), kotlinx.serialization (≈ `Codable`),
  Play Billing 9 + Block Store (`:core:billing`), ZXing core (QR), PdfDocument + StaticLayout (`:core:pdf`).

## Modules (1:1 with iOS packages)

| Module | iOS twin | Rule |
|---|---|---|
| `:core:domain` | `InvoiceCore` | Pure JVM (no Android SDK). Tests run on the JVM in seconds. |
| `:core:data` | `InvoiceData` | Room entities/DAOs matching `spec/schema/db/schema.sql`; `exportSchema = true`. |
| `:core:pdf` | `InvoicePDF` | Same templates / layout spec as iOS. |
| `:core:billing` | `InvoiceBilling` | Same state machine (`spec/billing.md`). |
| `:core:designsystem` | `InvoiceUI` (design system) | Theme from `spec/design/tokens.json`. |
| `:app` | app target + `InvoiceUI` screens | Screens, routers, `AppContainer`, `Session`. Folders match InvoiceUI's. |

## Kotlin rules that differ from Swift

- `BigDecimal.equals` compares scale (`2.0 != 2.00`): **always use `compareTo`**.
- `BigDecimal.divide()` without a scale and `RoundingMode` throws on non-terminating results: always pass both,
  or use the core `round()` helper.
- `data class` is a reference type with value equality; mutate via `copy()`. Keep domain types immutable (`val`).
- `java.util.UUID.toString()` is lowercase (matches the spec); never uppercase it.
- Use `java.time.LocalDate` for invoice dates (native on minSdk 26).

## Android lifecycle checklist (no iOS equivalent)

- **Configuration change** (rotation, dark mode, locale, window resize) recreates the Activity. State in a
  `ViewModel` survives; `remember {}` does not — use `rememberSaveable {}` for UI-only state.
- **Process death**: the OS may kill the app in the background and later restore the back stack without memory.
  Keep draft IDs in `SavedStateHandle`; drafts autosave to Room. Test with Developer options →
  "Don't keep activities".
- **Large screens**: apps targeting SDK 36 cannot lock orientation/resizability on screens ≥ 600 dp. Every screen
  must work at compact, medium and expanded widths.

## Commands

```sh
make test-core-android    # all spec fixtures on the JVM (same count as iOS)
make test-unit-android    # every JVM test + Android Lint + the R8 release build
make test-device-android  # on a running emulator/device: PDF renderer (PDFBox text checks) + Compose UI smoke tests
make pdf-samples-android  # review PDFs from the Android renderer
```

- JDK 21 (`JAVA_HOME=/opt/homebrew/opt/openjdk@21/...` here) and the SDK in `android/local.properties` (gitignored).
- An emulator without Android Studio: `sdkmanager "emulator" "system-images;android-36;google_apis;arm64-v8a"`,
  `avdmanager create avd -n ib_phone -k …`, `emulator -avd ib_phone -no-window`.
- UI tests launch with the `inMemory` / `seed` extras (≈ `-inMemory`, `-seed IN`); release builds ignore them.
- Compose test tags are the iOS accessibility identifiers. A tag on a child of a `mergeDescendants` node is
  invisible to tests: tag the merged node.
