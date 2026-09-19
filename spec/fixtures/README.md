# Golden fixtures

The answer key shared by iOS (`swift test` in `InvoiceCore`) and Android (`./gradlew :core:domain:test`).
Every file is validated by `make validate-spec` against `spec/schema/fixtures.schema.json`.

## File format

```json
{ "$schema": "../../schema/fixtures.schema.json", "kind": "tax", "description": "…", "cases": [ … ] }
```

| Kind | What it tests | Spec section |
|---|---|---|
| `tax` | `TaxEngine.compute` end to end | `spec/tax/ENGINE.md` §1–4 |
| `rounding` | `round(x, mode)` | §2.2 |
| `distribute` | `distribute` / `allocateProportional` | §2.3–2.4 |
| `format` | money, percent and quantity formatting | §7.1–7.2 |
| `words` | amount in words | §7.3 |
| `validation` | GSTIN and UK VAT number validation | §8 |
| `numbering` | invoice number patterns and periods | §5 |
| `status` | derived document status | §6 |
| `upi` | UPI payment links | §9 |

## How runners compare results

1. Run the function under test with `input` (for `tax`: load the config named in `config`, e.g. `IN@2025-09-22`
   → `spec/tax/IN.json` with that `configVersion`).
2. **Subset match:** every key in `expected` must exist in the actual output with an equal value; extra keys in the
   actual output are allowed. Objects compare recursively with the same rule.
3. **Arrays** must have the same length and compare element by element, in order, recursively.
4. `null` in `expected` means the actual value must be `null`/absent.
5. Money is compared as integers (minor units); rates as canonical decimal strings (`"9"`, `"2.5"`, `"0"`).
6. The test name is the case `id`, so a failure points straight at the fixture.

## Adding or changing cases

- Derive expected values from `ENGINE.md` and the country rules, never from app output.
- `tax` cases need an `explain` string with the arithmetic, so a CA or accountant can review them.
- New and changed cases start as `"reviewed": false`; a professional review flips them to `true`.
- Case ids are unique across all files (the validator enforces this).
- The fixture count per kind printed by `make validate-spec` is the parity target for both platforms.
