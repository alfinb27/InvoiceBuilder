# ADR-0002: Architecture pattern

- **Status:** Accepted
- **Date:** 2026-09-19

## Context
Both apps must stay structurally similar so the Android port is mechanical.

## Options considered
1. MVVM with one-way data flow (state value + intent methods + observable view model).
2. TCA on iOS + an MVI library on Android.
3. Views bound directly to @Observable models ("MV").
4. VIPER / full Clean layers.

## Decision
Option 1 on both platforms, plus thin domain services only where an operation spans repositories
(`IssueDocument`: allocate number → freeze snapshots → count toward free tier → schedule reminder, one transaction).

## Consequences
- `@Observable` view model ↔ Jetpack `ViewModel` + `StateFlow<UiState>` map one-to-one.
- View models are testable without UI; pure core logic stays out of view models.

## Revisit when
State and side effects become hard to reason about (most likely with cross-platform sync).
