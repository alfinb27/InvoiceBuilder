# Shared spec

The single source of truth for behaviour both apps must share. Platform code implements it; it never
redefines it. Start here before changing anything about money, tax, numbering, status, backups or billing.

| Path | Contents |
|---|---|
| `schema/tax-config.schema.json` | Shape of country tax configs |
| `schema/domain.schema.json` | Persisted entities (JSON form) |
| `schema/backup.schema.json` | Portable `.invoicebackup` file |
| `schema/fixtures.schema.json` | Golden fixture files |
| `schema/db/` | SQLite DDL: `schema.sql` (current) + numbered `migrations/` |
| `tax/IN.json`, `GB.json`, `GENERIC.json` | Country tax configs (data-driven rules) |
| `tax/ENGINE.md` | Normative tax engine, numbering, status, formatting and validation rules |
| `billing.md` | Entitlements, free tier, purchase state machine |
| `reference/` | Countries (ISO 3166-1), currencies (ISO 4217 subset), units (GST UQC + service units) |
| `pdf/labels/en.json` | PDF label strings |
| `design/tokens.json` | Colours, type, spacing, status chip colours, PDF paper sizes |
| `fixtures/` | Golden test cases (see `fixtures/README.md`) |
| `samples/` | Sample files (e.g. a valid backup) used by both platforms' tests |
| `tools/` | Validation and sync tooling (`make validate-spec`, `make sync-spec`) |

## Versioning rules

- **Tax configs** carry `configVersion` (the date the rules take effect). A rule change for a new date is a **new
  config version**; documents store `taxConfigRef` (`IN@2025-09-22`) so issued invoices never change.
  Rates carry `effectiveFrom`/`effectiveTo`; the engine picks by supply date.
- `reviewStatus` stays `draft` until a CA (India) / accountant (UK) has reviewed the config and its fixtures.
- **Schemas** (`schemaVersion`) change only with an ADR; additive changes preferred.
- **Database**: a change is a new migration `NNNN_name.sql` + the same change in `schema.sql`. After 1.0, migrations
  are additive only (ADR-0015). `make validate-spec` checks `schema.sql` = all migrations applied in order.
- **Backups** carry `formatVersion` and `dbSchemaVersion`; readers must accept older versions.
- **Fixtures**: see `fixtures/README.md`.
