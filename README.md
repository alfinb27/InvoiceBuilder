# InvoiceBuilder

An offline-first invoicing app for sole traders, freelancers and small shops in India and the UK.
Native iOS/iPadOS (Swift, SwiftUI, GRDB, StoreKit 2, iCloud sync) first, then native Android
(Kotlin, Compose, Room, Play Billing). Both apps implement one shared **spec**.

- **Plan:** [`docs/plan.md`](docs/plan.md) (approved 2026-09-19)
- **Decisions:** [`docs/decisions/`](docs/decisions/)
- **Spec (source of truth for behaviour):** [`spec/`](spec/)
- **Feature parity:** [`docs/parity.md`](docs/parity.md)

## Repo layout

| Path | What lives there |
|---|---|
| `spec/` | JSON Schemas, tax configs, reference data, DB schema, PDF labels, design tokens, golden fixtures, tooling |
| `docs/` | Plan, ADRs, compliance notes, spike reports, product notes |
| `ios/` | iOS/iPadOS app (from Phase 1) |
| `android/` | Android app (from Phase 7) |

## Common commands

```sh
make setup           # install spec tooling (once; needs Node 20+ and the sqlite3 CLI)
make validate-spec   # validate configs + fixtures against the schemas and consistency rules
```

Status: **Phase 0 desk work complete** — see [`docs/phase-0-status.md`](docs/phase-0-status.md) for what needs accounts, Xcode, Android Studio or devices.
