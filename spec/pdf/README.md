# PDF spec

Decision: **native drawing from a shared layout spec** (ADR-0006, `docs/spikes/pdf-spike.md`).

| Path | Contents |
|---|---|
| `labels/en.json` | Label strings used by every template |
| `fonts/` | Bundled **static** fonts (Noto Sans + Noto Sans Devanagari, Regular/SemiBold/Bold) and `OFL.txt`. Do not switch to variable fonts: they broke text extraction and file size in the spike. |
| `layout/` | Template definitions as data (`schema/pdf-layout.schema.json`): the blocks to draw, in order, plus style tokens — `classic`, `modern`, `minimal`, `compact` |
| `RENDERING.md` | **Normative:** the view model (what each block says and how it is formatted), the template format, pagination, fonts, the UPI QR and caching |

Renderer contract (both platforms): input = PDF view model (pre-formatted strings built from `ComputedDocument`,
snapshots and labels) + template definition → A4/Letter PDF with repeated table header, unsplittable rows, totals block
kept whole, "Page x of y", selectable text (₹, £, Devanagari).
