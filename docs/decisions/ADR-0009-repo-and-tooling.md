# ADR-0009: Repo and project tooling

- **Status:** Accepted
- **Date:** 2026-09-19

## Decision
- Monorepo: `spec/`, `docs/`, `ios/`, `android/`; path-filtered CI.
- iOS: plain Xcode project with synchronized folders; nearly all code in local Swift packages.
- Tests read fixtures straight from `spec/`; bundled runtime copies are produced by `make sync-spec` and
  CI fails if they drift.
- Spec tooling is Node-based (`spec/tools`, ajv): Node is preinstalled on CI runners and the dev machine, and
  it is a dev-only dependency that never ships in either app.

## Revisit when
Targets/configurations change often (extensions, widgets) → Tuist.
