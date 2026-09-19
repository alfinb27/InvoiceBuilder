# ADR-0005: State management and navigation

- **Status:** Accepted
- **Date:** 2026-09-19

## Decision
- **iOS:** `@Observable @MainActor` view models with one `State` value; GRDB `ValueObservation` as
  `AsyncSequence`; forms edit a value-type `DocumentDraft`; pure `TaxEngine.compute` on every change; drafts
  autosave (500 ms debounce); `NavigationStack(path:)` with a router per tab.
- **Android:** `ViewModel` exposes `StateFlow<UiState>` via `stateIn(viewModelScope, WhileSubscribed(5_000), …)`;
  Compose collects with `collectAsStateWithLifecycle()`; one-off effects are state the UI consumes and clears;
  **Navigation 3** (back stack owned as a list of keys ≈ `NavigationStack(path:)`).

## Consequences
Android-only concerns handled explicitly: configuration changes (`rememberSaveable`), process death
(`SavedStateHandle` + autosave).

## Revisit when
Navigation 3 blocks deep links or result passing → Navigation Compose 2 with type-safe routes.
