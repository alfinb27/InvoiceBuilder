# ADR-0004: Dependency injection

- **Status:** Accepted
- **Date:** 2026-09-19

## Context
About 10 services; developer new to Android; builds should stay fast and understandable.

## Options considered
iOS: hand-written container via `Environment`, swift-dependencies, Factory. Android: manual `AppContainer`,
Hilt (compile-time DI via annotation processing), Koin (runtime service locator).

## Decision
Manual injection on both. iOS: `AppDependencies` built in `App.init`, passed via `Environment`, view models get
dependencies through `init`. Android: `AppContainer` created in the `Application` subclass; view models built
with `viewModelFactory { initializer { … } }`.

## Consequences
One mental model on both platforms; tests pass fakes directly; no annotation-processing step to learn.

## Revisit when
~15+ Android view models, or WorkManager workers need injected dependencies → migrate to Hilt.
