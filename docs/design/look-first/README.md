# Pick a look first: clickable prototype

The prototype for #58: new users pick how their invoice looks, then fill in their first invoice one question per
screen, with the live invoice above each question. It replaces the ADR-0020 three-stage setup. Nothing here is app
code; the spec, ADR and native work wait until the prototype has been tried with people who don't know GST/VAT.

- **Try it:** the design canvas at https://claude.ai/artifact/Xb1T4DskQMYVRfeH7ipcyu (private; share it from the page's
  Share menu before sending it to testers). Select the phone and press Play.
- **Test script:** ask someone who doesn't know GST/VAT to "send Ravi an invoice for 2 logo designs at ₹2,500, due in
  a week" without help. Note where they stop, what they ask and how long it takes. Run it with and without a GSTIN.
  For the UK, tap Change next to "Invoices in ₹" on the Pick a look screen.
- **Plan:** [`plan.md`](plan.md) (Phase A is this prototype; Phases B–D are the spec, iOS and Android work).

## Files

| File | What it is |
|---|---|
| `prototype/canvas.json` | Canvas layout: which boards sit where, and the sticky notes |
| `prototype/Main.dc.html` | The whole flow on one 390×844 phone: Welcome, Pick a look, the 7 steps, Looks good?, Sent, the 3-step repeat invoice and the sheets |
| `prototype/Invoice.dc.html` | The invoice page in the four layouts (modern, classic, minimal, compact), with the focus ring and zoom the steps use |
| `prototype/Screens-India.dc.html`, `Screens-UK.dc.html` | Rows of `Main` instances started on each screen, for review at a glance |
| `check.js` | Runs the prototype logic in Node: every `{{ }}` hole resolves, and four flows (India/UK, with and without tax) reach Sent with the right totals |

The `.dc.html` files are the canvas's source format. They load `support.js` from the canvas, so they don't open on their
own in a browser. To change the prototype, edit them and republish to the same canvas link. To check the logic:

```sh
node docs/design/look-first/check.js   # prints ALL CHECKS PASSED
```

The tax maths here is simplified, enough for the totals to look right. The apps use the real engine in
`spec/tax/ENGINE.md`.
