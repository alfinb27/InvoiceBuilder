# Architecture decision records

| ADR | Decision | Status |
|---|---|---|
| [0001](ADR-0001-build-order-and-code-sharing.md) | Two native apps + shared spec; iOS first | Accepted |
| [0002](ADR-0002-architecture-pattern.md) | MVVM with one-way data flow + thin domain services | Accepted |
| [0003](ADR-0003-persistence.md) | GRDB (iOS) + Room (Android), one SQLite schema | Accepted |
| [0004](ADR-0004-dependency-injection.md) | Manual DI on both platforms | Accepted |
| [0005](ADR-0005-state-and-navigation.md) | Observable view models, Navigation 3 | Accepted |
| [0006](ADR-0006-pdf-approach.md) | Native PDF drawing from a shared layout spec | Accepted (desk spike) |
| [0007](ADR-0007-money-numbers-dates.md) | Minor units + Decimal, spec'd rounding, calendar dates | Accepted |
| [0008](ADR-0008-billing-and-entitlements.md) | One non-consumable; 15 free issued invoices | Accepted |
| [0009](ADR-0009-repo-and-tooling.md) | Monorepo, synchronized Xcode folders, Node spec tooling | Accepted |
| [0010](ADR-0010-minimum-os-versions.md) | iOS 18, Android minSdk 26 / target 36 | Accepted |
| [0011](ADR-0011-crash-reporting-and-privacy.md) | First-party diagnostics only | Accepted |
| [0012](ADR-0012-testing-strategy.md) | Fixture-driven core tests on both platforms | Accepted |
| [0013](ADR-0013-backup-restore-reminders.md) | Portable JSON backup; local reminders | Accepted |
| [0014](ADR-0014-ipad-support.md) | Universal, adaptive iPad app | Accepted |
| [0015](ADR-0015-icloud-sync.md) | SQLiteData sync on GRDB, device-owned series | Accepted in code (device run pending) |
| [0017](ADR-0017-ios-release-and-lessons-for-android.md) | iOS 1.0 scope; lessons the Android port inherits | Accepted |
| [0018](ADR-0018-android-ui-architecture.md) | Android UI as iOS: routers + snapshot state; compile/target SDK 37 | Accepted |
| [0019](ADR-0019-device-identity-across-os-backups.md) | A device marker outside OS backups; a copied database takes a new device id | Accepted |
| [0020](ADR-0020-friendly-first-run-and-visual-design.md) | Friendly first run (welcome, 3-stage setup, guided builder, Review & send) and the coral/peach theme with bundled UI fonts | Accepted |

New decisions: copy [`TEMPLATE.md`](TEMPLATE.md) to the next number.
