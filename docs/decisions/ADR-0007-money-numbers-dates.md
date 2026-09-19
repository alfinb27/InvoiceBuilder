# ADR-0007: Money, numbers and dates

- **Status:** Accepted
- **Date:** 2026-09-19

## Decision
- Stored amounts: `Int64` minor units + ISO-4217 code; exponents from `spec/reference/currencies.json`.
- Rates and quantities: decimal strings in JSON/SQLite, parsed into `Decimal` / `BigDecimal` for maths.
  Intermediate values keep ≥ 20 significant digits; rounding happens only where `spec/tax/ENGINE.md` says.
- Rounding modes are defined by meaning (`halfAwayFromZero`, `halfEven`, `towardZero`) and implemented once per
  platform, proven by fixtures including negative values and exact .5 boundaries. Library enum names are not
  trusted (Foundation `.down` ≠ Java `DOWN` for negatives).
- Allocations (invoice discount, invoice-level tax totals) use the largest-remainder method.
- Invoice dates are calendar dates (`YYYY-MM-DD`); audit timestamps are epoch ms UTC; UUIDs are lowercase.

## Consequences
No floating point anywhere in money paths; both platforms produce byte-identical amounts for the same input.
