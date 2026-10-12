# InvoiceBuilder — repo rules

Offline-first invoicing app for India (GST) and the UK (VAT). Native iOS/iPadOS first, native Android
second. Both apps implement the shared `spec/`. The approved plan is `docs/plan.md`; decisions are ADRs in
`docs/decisions/`.

## Golden rules (apply on every platform)

1. **Spec first.** Any behaviour change starts in `spec/` (schema, config, `ENGINE.md`, fixtures), then iOS,
   then Android. Update `docs/parity.md` in the same change.
2. **Never `Double`/`Float` for money, rates or quantities.** Money is `Int64` minor units + ISO-4217 code.
   Rates and quantities are decimal strings parsed into `Decimal` / `BigDecimal`. Round only through the core
   `round(value, scale, mode)` using the spec's modes: `halfAwayFromZero`, `halfEven`, `towardZero`.
3. **Identifiers and time:** UUIDs are lowercase strings. Invoice dates are calendar dates (`YYYY-MM-DD`,
   no timezone). Audit timestamps are epoch milliseconds UTC.
4. **Issued documents are never renumbered or hard-deleted.** Numbers are allocated only at issue, only from
   a series this device owns. "Void" keeps the number.
5. **Sync-safe schema** (SQLiteData/CloudKit rules, `docs/spikes/sync-spike.md`): primary keys are
   `TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE`; no UNIQUE constraints except primary keys; foreign keys declare
   `ON DELETE CASCADE | SET NULL | SET DEFAULT` (never RESTRICT/NO ACTION); no CloudKit reserved column names
   (`creationDate`, `modificationDate`, `recordID`, `recordType`, `etag`, …); no value-list `CHECK (col IN ('a', 'b'))` on
   synced tables — enforce value lists in app code and the JSON Schemas (a newer app version's values must still insert
   on older devices). `make validate-spec` enforces all of this. After 1.0, migrations only add tables
   or add columns that are nullable or have a `DEFAULT … ON CONFLICT REPLACE`; never rename or drop.
6. **Same names on both platforms** for modules, types and functions (`TaxEngine.compute`,
   `DocumentRepository`, `IssueDocument`). Port file by file, keeping names.
7. **Decision-level changes need an ADR** (`docs/decisions/ADR-NNNN-*.md`, from `TEMPLATE.md`).

## Where things live

| Need | Location |
|---|---|
| Domain / backup / tax-config schemas | `spec/schema/*.schema.json` |
| Database DDL and migrations | `spec/schema/db/` |
| Country tax configs | `spec/tax/IN.json`, `GB.json`, `GENERIC.json` |
| Tax engine behaviour (normative) | `spec/tax/ENGINE.md` |
| Documents: drafts, issuing, duplicate, convert, payments, void (normative) | `spec/documents.md` |
| Reminders (normative) | `spec/reminders.md` |
| Backup and restore (normative) | `spec/backup.md` |
| iCloud sync and numbering on several devices (normative) | `spec/sync.md` |
| Setup: onboarding, clients, catalogue, numbering (normative) | `spec/setup.md` |
| Entitlements and free tier | `spec/billing.md` |
| Golden fixtures | `spec/fixtures/**` (format: `spec/fixtures/README.md`) |
| Compliance sources | `docs/compliance/` |

## Commands

```sh
make setup            # once: installs spec tooling (Node, spec/tools)
make validate-spec    # schemas (strict), configs, fixtures, samples, DB schema + sync rules (needs the sqlite3 CLI)
```

Platform commands live in `ios/CLAUDE.md` and `android/CLAUDE.md`.

## Working on fixtures

- A fixture is the answer key for both platforms. Expected values must be derived from `ENGINE.md` and the
  country rules, never copied from an implementation's output.
- Every tax case carries an `explain` string showing the arithmetic, so a CA or accountant can review it.
- New or changed fixtures stay `"reviewed": false` until a professional has checked them.
- Run `make validate-spec` before committing; it checks schema validity and that totals add up.
