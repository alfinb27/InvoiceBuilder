# PDF spec

Decision: **native drawing from a shared layout spec** (ADR-0006, `docs/spikes/pdf-spike.md`).

| Path | Contents |
|---|---|
| `labels/en.json` | Label strings used by every template |
| `fonts/` | Bundled **static** fonts (Noto Sans + Noto Sans Devanagari, Regular/SemiBold/Bold) and `OFL.txt`. Do not switch to variable fonts: they broke text extraction and file size in the spike. |
| `layout/` | *(Phase 3)* Template definitions as data: block list (header, parties, items table, totals, tax summary, payment/UPI, notes, signature, footer) + style tokens per template (`classic`, `modern`, `minimal`, `compact`) |

Renderer contract (both platforms): input = PDF view model (pre-formatted strings built from `ComputedDocument`,
snapshots and labels) + template definition → A4/Letter PDF with repeated table header, unsplittable rows, totals block
kept whole, "Page x of y", selectable text (₹, £, Devanagari).
