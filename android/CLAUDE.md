# Android app rules

Read the root `CLAUDE.md` first. The Android app is a port of the iOS app (Phase 7): **port from the Swift
file, keep the names**, and prove behaviour with the same `spec/fixtures`. The developer is an experienced
iOS engineer, so explanations and code comments should map Android concepts to their iOS equivalents.

## Stack

- Kotlin 2.x (K2), Jetpack Compose + Material 3 (+ Material 3 Adaptive), minSdk 26, target/compile SDK 36.
- Gradle Kotlin DSL, one version catalog (`gradle/libs.versions.toml` ≈ pinned SPM versions), AGP 9, KSP
  (compile-time code generation ≈ Swift macros).
- `ViewModel` + `StateFlow<UiState>` (≈ `@Observable` view model), Navigation 3 (back stack you own ≈
  `NavigationStack(path:)`), manual DI via `AppContainer` in the `Application` subclass (≈ `AppDependencies`).
- Room (SQLite, same schema as GRDB), DataStore (≈ typed `UserDefaults`), WorkManager (reminders),
  kotlinx.serialization (≈ `Codable`), Play Billing Library 8+, ZXing core (QR).

## Modules (1:1 with iOS packages)

| Module | iOS twin | Rule |
|---|---|---|
| `:core:domain` | `InvoiceCore` | Pure JVM (no Android SDK). Tests run on the JVM in seconds. |
| `:core:data` | `InvoiceData` | Room entities/DAOs matching `spec/schema/db/schema.sql`; `exportSchema = true`. |
| `:core:pdf` | `InvoicePDF` | Same templates / layout spec as iOS. |
| `:core:billing` | `InvoiceBilling` | Same state machine (`spec/billing.md`). |
| `:core:designsystem` | `InvoiceUI` (design system) | Theme from `spec/design/tokens.json`. |
| `:app` | app target | Screens, navigation, `AppContainer`. |

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

## Commands (once the project exists)

```sh
./gradlew :core:domain:test          # all spec fixtures on the JVM (same count as iOS)
./gradlew testDebugUnitTest lint     # unit tests (Room migrations, view models, Roborazzi) + Android Lint
./gradlew connectedDebugAndroidTest  # instrumented tests on an emulator/device
```

Requires a JDK 17+ and the Android SDK (install Android Studio).
