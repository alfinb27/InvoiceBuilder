# ADR-0018: Android UI architecture, as built in Phase 7

- **Status:** Accepted
- **Date:** 2026-10-09
- **Amends:** ADR-0005 (Android half), plan D10 (target SDK)

## Context
ADR-0005 planned the Android UI as `ViewModel` + `StateFlow<UiState>` per screen with a Navigation 3 back stack.
Porting InvoiceUI file by file (CLAUDE.md rule 6) showed that the iOS shape — long-lived routers holding all
navigation state, view models holding drafts, list/detail split views — maps onto Compose more directly than the
planned one, and keeps the two apps reviewable side by side. Separately, the current Compose BOM (2026.09) requires
compiling against API 37.

## Options considered
1. **As planned:** one androidx `ViewModel` per screen exposing `StateFlow<UiState>`; Navigation 3 back stack;
   `ListDetailPaneScaffold`.
2. **As iOS:** routers (`AppRouter`, `ListDetailRouter`, `DocumentsRouter`, `SettingsRouter`) holding Compose
   snapshot state (`mutableStateOf` ≈ `@Observable`), owned by the `Session`, which the activity-scoped `AppModel`
   (an `AndroidViewModel`) owns; screen models as plain classes with snapshot state, the same names and intents as
   iOS; our own `ListDetail` layout switching at the 600 dp token.

## Decision
Option 2.

- **State:** snapshot state in routers and screen models. Compose recomposes on reads exactly as SwiftUI does with
  `@Observable`; no `UiState` copy per screen, no `StateFlow` plumbing between view model and composable. Room
  observation stays a `Flow`, collected with `collectAsStateWithLifecycle`.
- **Lifetime:** `AppModel` is an `AndroidViewModel`, so rotation, folding, dark mode and window resizing keep the
  session, the routers and every open editor. Editor and document models are held by `Session.retained(key)` and
  released when the screen closes for good (not when it is merely recomposed by a configuration change).
- **Process death:** drafts are in Room within 500 ms and flushed on `ON_STOP`, so no data is lost; the open screen is
  not restored (the app starts on Home). Acceptable for v1; `SavedStateHandle` for the router is the follow-up if
  testers notice.
- **Navigation:** the router *is* the back stack (selection, open editor). System Back closes the detail pane on
  phones (`BackHandler`). `NavigationSuiteScaffold` gives bottom bar / rail / drawer by window size.
- **Modals:** `EditorSheet` (full-screen dialog on phones, a centred card on wide windows) ≈ `.sheet`;
  `ConfirmDialog` ≈ `.confirmationDialog`.
- **SDK levels:** `compileSdk = 37` and `targetSdk = 37` (Lint's `OldTargetApi`); `minSdk = 26` unchanged.
- **Platform differences kept deliberately:**
  - Reminders: one daily WorkManager job posts the reminders due (ADR-0013), instead of iOS's 50 pre-scheduled
    notifications.
  - Diagnostics: `ApplicationExitInfo` (crashes, ANRs) replaces MetricKit; shared only on request (ADR-0011).
  - "Mark as sent?" is offered when the user returns from the share chooser or print dialog: Android does not report
    whether a share completed.
  - Test launches (`inMemory`, `seed` extras ≈ `-inMemory`, `-seed IN`) work only in debuggable builds, because other
    apps can send extras to an exported activity.

## Consequences
- Reviewing a feature means reading two files with the same name and the same intents, one Swift, one Kotlin.
- Fewer Android-idiomatic layers (no per-screen androidx `ViewModel`), so a newcomer from Android may look for them;
  `android/CLAUDE.md` explains the mapping.
- Process-death restore of the open screen is not there yet (see above).

## Revisit when
Testers lose their place after process death often enough to matter, or deep links (e.g. from a notification to a
specific payment) need a real back stack — then Navigation 3 with the routers' state as its keys.
