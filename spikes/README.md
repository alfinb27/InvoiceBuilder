# Spikes (throwaway)

Code here exists only to answer a Phase 0 question; nothing here ships. Results and decisions live in
`docs/spikes/*.md` and the ADRs.

| Spike | Question | Report |
|---|---|---|
| `pdf/` | HTML templates (Option A) vs native drawing (Option B) | `docs/spikes/pdf-spike.md`, ADR-0006 |
| `sync/` | Does SQLiteData's CloudKit sync work on our GRDB schema? | `docs/spikes/sync-spike.md`, ADR-0015 |

`pdf/`: first `mkdir -p pdf/fonts && cp ../spec/pdf/fonts/* pdf/fonts/`; then `npm install && npx playwright install chromium`, then `node render-chromium.mjs`;
`swiftc -O webkit/main.swift -o webkit/webkit-render && webkit/webkit-render $PWD`;
`swiftc -O native/main.swift -o native/native-render && native/native-render $PWD`.
View models in `pdf/viewmodels/` were generated from `spec/fixtures` by the reference calculator.
