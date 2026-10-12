#!/usr/bin/env node
// Validates the shared spec:
//   * every JSON file parses and is covered by a JSON Schema (Ajv strict mode) or a dedicated check;
//   * tax-config cross-references, reference data, backup samples and fixture consistency;
//   * the SQLite schema: schema.sql equals all migrations applied in order (compared structurally), and every synced
//     table follows the sync-safe rules (ADR-0015, docs/spikes/sync-spike.md).
// Usage: node spec/tools/validate.mjs   (or `make validate-spec` from the repo root). Needs Node 20+ and the sqlite3 CLI.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import Ajv2020 from "ajv/dist/2020.js";

const SPEC = join(dirname(fileURLToPath(import.meta.url)), "..");
const errors = [];
const fail = (file, msg) => errors.push(`${relative(SPEC, file) || "spec"}: ${msg}`);
const readJSON = (file) => {
  try { return JSON.parse(readFileSync(file, "utf8")); }
  catch (e) { fail(file, `invalid JSON (${e.message})`); return null; }
};
const walk = (dir, ext = ".json") => readdirSync(dir).flatMap((name) => {
  if (name === "node_modules" || name.startsWith(".")) return [];
  const p = join(dir, name);
  return statSync(p).isDirectory() ? walk(p, ext) : p.endsWith(ext) ? [p] : [];
});
const sum = (xs) => xs.reduce((a, b) => a + b, 0);

// ---------- JSON Schemas (strict: unknown or misplaced keywords are errors, not silently ignored) ----------
const ajv = new Ajv2020({ allErrors: true, strict: true });
const schemaDir = join(SPEC, "schema");
const schemaFiles = walk(schemaDir).filter((f) => f.endsWith(".schema.json"));
for (const f of schemaFiles) {  // add all first, so cross-file $refs resolve regardless of order
  const s = readJSON(f);
  if (s) { try { ajv.addSchema(s, relative(schemaDir, f)); } catch (e) { fail(f, `schema rejected: ${e.message}`); } }
}
for (const f of schemaFiles) {  // then compile each one, surfacing strict-mode errors even for unused schemas
  try { ajv.getSchema(relative(schemaDir, f)); } catch (e) { fail(f, `schema does not compile: ${e.message}`); }
}
const validateWith = (schemaName, data, file) => {
  let v;
  try { v = ajv.getSchema(schemaName); } catch (e) { fail(file, `schema ${schemaName}: ${e.message}`); return false; }
  if (!v) { fail(file, `schema ${schemaName} not found`); return false; }
  if (!v(data)) { for (const e of v.errors) fail(file, `${e.instancePath || "/"} ${e.message}`); return false; }
  return true;
};

// ---------- every JSON file under spec/ ----------
const DATA_SCHEMAS = [
  [/^reference\/currencies\.json$/, "currencies.schema.json"],
  [/^reference\/countries\.json$/, "countries.schema.json"],
  [/^reference\/units\.json$/, "units.schema.json"],
  [/^pdf\/labels\/[a-z]{2,3}(-[A-Z]{2})?\.json$/, "pdf-labels.schema.json"],
  [/^pdf\/layout\/[a-z]+\.json$/, "pdf-layout.schema.json"],
  [/^design\/tokens\.json$/, "design-tokens.schema.json"],
  [/^design\/rate-chips\.json$/, "rate-chips.schema.json"],
];
const CHECKED_BELOW = [/^schema\//, /^tax\//, /^fixtures\//, /^samples\//, /^tools\//];
for (const f of walk(SPEC)) {
  const rel = relative(SPEC, f);
  const data = readJSON(f);
  if (!data) continue;
  const mapped = DATA_SCHEMAS.find(([re]) => re.test(rel));
  if (mapped) validateWith(mapped[1], data, f);
  else if (!CHECKED_BELOW.some((re) => re.test(rel)))
    fail(f, "JSON file is not covered by any schema — add a schema and a DATA_SCHEMAS entry in spec/tools/validate.mjs");
}

// ---------- tax configs ----------
const configs = {};
for (const f of walk(join(SPEC, "tax"))) {
  const c = readJSON(f); if (!c) continue;
  if (!validateWith("tax-config.schema.json", c, f)) continue;
  configs[`${c.country === "ZZ" ? "GENERIC" : c.country}@${c.configVersion}`] = c;
  const ids = (arr) => new Set(arr.map((x) => x.id));
  const dupes = (arr, key) => arr.map((x) => x[key]).filter((v, i, a) => a.indexOf(v) !== i);
  for (const [name, arr, key] of [["rate", c.rates, "id"], ["registration", c.registrations, "id"],
    ["supplyType", c.supplyTypes, "id"], ["region", c.regions ?? [], "code"]]) {
    for (const d of dupes(arr, key)) fail(f, `duplicate ${name} ${d}`);
  }
  const supply = ids(c.supplyTypes), regs = ids(c.registrations), notes = new Set(Object.keys(c.notesCatalog));
  const noteRefs = [...c.registrations.flatMap((r) => r.notes ?? []), ...c.componentRules.flatMap((r) => r.notes ?? []),
    ...(c.reverseCharge.notes ?? [])];
  for (const n of noteRefs) if (!notes.has(n)) fail(f, `note "${n}" is not in notesCatalog`);
  const conds = [...c.componentRules.map((r) => r.when), ...c.checks.map((k) => k.when ?? {})];
  for (const d of c.supplyTypeDefaults ?? []) if (!supply.has(d.supplyType)) fail(f, `unknown supplyType "${d.supplyType}" in supplyTypeDefaults`);
  for (const w of conds) {
    for (const s of w.supplyType ?? []) if (!supply.has(s)) fail(f, `unknown supplyType "${s}" in condition`);
    for (const r of w.sellerRegistration ?? []) if (!regs.has(r)) fail(f, `unknown registration "${r}" in condition`);
  }
  if ((c.ratesFrom ?? "config") === "config" && c.rates.length === 0) fail(f, "rates must not be empty when ratesFrom=config");
  if (c.componentRules.some((r) => r.components === "fromRate") && c.ratesFrom !== "business")
    fail(f, `components "fromRate" requires ratesFrom=business`);
  for (const r of c.rates) {
    if (c.ratesFrom !== "business" && r.percent === undefined) fail(f, `rate ${r.id} needs percent`);
    if (r.effectiveTo && r.effectiveTo < r.effectiveFrom) fail(f, `rate ${r.id} effectiveTo before effectiveFrom`);
  }
  for (const t of c.taxIdFormats ?? []) { try { new RegExp(t.pattern); } catch { fail(f, `bad regex in ${t.id}`); } }
  if (c.numbering.allowedPattern) { try { new RegExp(c.numbering.allowedPattern); } catch { fail(f, "bad numbering.allowedPattern"); } }
}
const configFamilies = new Set(Object.keys(configs).map((k) => k.split("@")[0]));

// ---------- reference data (shapes are checked by their schemas above) ----------
const currencies = readJSON(join(SPEC, "reference/currencies.json"))?.currencies ?? [];
const currencyCodes = new Set(currencies.map((c) => c.code));
if (currencyCodes.size !== currencies.length) fail(join(SPEC, "reference/currencies.json"), "duplicate currency code");
for (const c of Object.values(configs)) if (c.currency && !currencyCodes.has(c.currency))
  fail(join(SPEC, "reference/currencies.json"), `config currency ${c.currency} missing`);
// ---------- PDF templates ----------
// One layout file per templateId the domain schema allows, each declaring that id (pdf/RENDERING.md §2).
const templateIDs = readJSON(join(SPEC, "schema/domain.schema.json"))?.$defs?.Business?.properties?.templateId?.enum
  ?? [];
const layoutDir = join(SPEC, "pdf/layout");
const layouts = walk(layoutDir).map((f) => [f, readJSON(f)]).filter(([, data]) => data);
for (const [f, layout] of layouts) {
  const name = relative(layoutDir, f).replace(/\.json$/, "");
  if (layout.id !== name) fail(f, `id "${layout.id}" does not match the file name "${name}"`);
}
for (const id of templateIDs) {
  if (!layouts.some(([, layout]) => layout.id === id)) fail(layoutDir, `no layout file for template "${id}"`);
}

// ---------- design tokens: contrast and font files (docs/design/design.md §8, ADR-0020) ----------
const tokensFile = join(SPEC, "design/tokens.json");
const tokens = readJSON(tokensFile);
const rgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
const luminance = (hex) => {
  const [r, g, b] = rgb(hex).map((v) => v / 255).map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (a, b) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};
const tint = (fg, bg, alpha) => `#${rgb(fg).map((f, i) => Math.round(alpha * f + (1 - alpha) * rgb(bg)[i])
  .toString(16).padStart(2, "0")).join("")}`;
// Text drawn on a fill; each pair must reach 4.5:1 in both themes.
const TEXT_PAIRS = [
  ["textPrimary", "background"], ["textPrimary", "surface"], ["textPrimary", "brandTint"], ["textPrimary", "tip"],
  ["textPrimary", "surfaceSubtle"], ["textPrimary", "surfaceMuted"], ["textSecondary", "background"],
  ["textSecondary", "surface"], ["textSecondary", "surfaceMuted"], ["textSecondary", "surfaceSubtle"],
  ["textSecondary", "brandTint"], ["brand", "background"], ["brand", "surface"], ["brandOn", "brand"],
  ["brandPressed", "brandTint"], ["tipOn", "tip"], ["success", "background"], ["warning", "background"],
  ["danger", "background"], ["info", "background"], ["success", "surface"], ["warning", "surface"],
  ["danger", "surface"], ["info", "surface"],
];
if (tokens?.color) {
  for (const theme of ["light", "dark"]) {
    const palette = tokens.color[theme] ?? {};
    for (const [fg, bg] of TEXT_PAIRS) {
      if (!palette[fg] || !palette[bg]) continue; // the schema reports missing keys
      const ratio = contrast(palette[fg], palette[bg]);
      if (ratio < 4.5) fail(tokensFile, `${theme}: ${fg} on ${bg} is ${ratio.toFixed(2)}:1, below 4.5:1`);
    }
    for (const [status, pair] of Object.entries(tokens.status ?? {})) {
      if (!Array.isArray(pair)) continue;
      const color = pair[theme === "light" ? 0 : 1];
      for (const ground of ["background", "surface"]) {
        if (!palette[ground]) continue;
        const ratio = contrast(color, tint(color, palette[ground], 0.12));
        if (ratio < 4.5) fail(tokensFile, `${theme}: status ${status} on its chip over ${ground} is ${ratio.toFixed(2)}:1, below 4.5:1`);
      }
    }
  }
  for (const role of Object.values(tokens.fonts ?? {})) {
    if (typeof role !== "object") continue;
    for (const name of Object.values(role.files ?? {}))
      if (!statSync(join(SPEC, "design/fonts", `${name}.ttf`), { throwIfNoEntry: false }))
        fail(tokensFile, `font file design/fonts/${name}.ttf is missing`);
  }
  for (const [name, style] of Object.entries(tokens.type ?? {}))
    if (!tokens.fonts?.[style.font]) fail(tokensFile, `type.${name}: unknown font "${style.font}"`);
}

// ---------- rate chips: every id is a rate of its config family ----------
const chipsFile = join(SPEC, "design/rate-chips.json");
const chips = readJSON(chipsFile);
for (const [family, entry] of Object.entries(chips?.families ?? {})) {
  const familyConfigs = Object.entries(configs).filter(([key]) => key.split("@")[0] === family).map(([, c]) => c);
  if (!familyConfigs.length) { fail(chipsFile, `unknown config family ${family}`); continue; }
  for (const id of entry.rates ?? [])
    if (!familyConfigs.some((c) => c.rates.some((r) => r.id === id))) fail(chipsFile, `${family}: rate "${id}" is not in its config`);
}

const countries = readJSON(join(SPEC, "reference/countries.json"))?.countries ?? [];
if (new Set(countries.map((c) => c.code)).size !== countries.length) fail(join(SPEC, "reference/countries.json"), "duplicate country");
const units = readJSON(join(SPEC, "reference/units.json"))?.units ?? [];
if (new Set(units.map((u) => u.id)).size !== units.length) fail(join(SPEC, "reference/units.json"), "duplicate unit id");

// ---------- fixtures ----------
const counts = {};
const seen = new Map();
function checkTaxCase(file, c) {
  if (!configs[c.config]) fail(file, `case ${c.id}: unknown config ${c.config}`);
  const x = c.expected; if (!x?.totals) return;
  const t = x.totals, where = `case ${c.id}`;
  if (["taxable", "tax", "roundOff", "total"].every((k) => k in t) && t.taxable + t.tax + t.roundOff !== t.total)
    fail(file, `${where}: taxable + tax + roundOff (${t.taxable + t.tax + t.roundOff}) != total (${t.total})`);
  if (x.taxLines && "tax" in t) {
    const charged = sum(x.taxLines.filter((l) => l.charged !== false).map((l) => l.tax));
    if (charged !== t.tax) fail(file, `${where}: sum of charged taxLines (${charged}) != totals.tax (${t.tax})`);
    const notCharged = sum(x.taxLines.filter((l) => l.charged === false).map((l) => l.tax));
    if ((t.taxNotCharged ?? 0) !== notCharged) fail(file, `${where}: taxNotCharged (${t.taxNotCharged ?? 0}) != ${notCharged}`);
  }
  if (["subtotal", "discount", "shipping", "taxable", "tax"].every((k) => k in t)) {
    const basis = t.subtotal - t.discount + t.shipping;
    const inclusive = x.inclusive ?? false;
    const expectedBasis = inclusive ? t.taxable + t.tax : t.taxable;
    if (basis !== expectedBasis) fail(file, `${where}: subtotal - discount + shipping (${basis}) != ${inclusive ? "taxable + tax" : "taxable"} (${expectedBasis})`);
  }
  if (x.lines && "taxable" in t && x.lines.every((l) => "taxable" in l)) {
    const lineTaxable = sum(x.lines.map((l) => l.taxable)) + (x.shipping?.taxable ?? 0);
    if (lineTaxable !== t.taxable) fail(file, `${where}: sum of line taxable (${lineTaxable}) != totals.taxable (${t.taxable})`);
  }
}

// ---------- backup fixtures: an independent reference for spec/backup.md §3 ----------
const COLLECTIONS = ["businesses", "clients", "catalogItems", "numberingSeries", "documents", "payments", "assets"];
const DOMAIN_DEF = { businesses: "Business", clients: "Client", catalogItems: "CatalogItem",
  numberingSeries: "NumberingSeries", documents: "Document", payments: "Payment", assets: "Asset" };
const pointerParts = (p) => p.split("/").slice(1).map((s) => s.replaceAll("~1", "/").replaceAll("~0", "~"));
function patchBackup(file, input) {
  if (("base" in input) === ("raw" in input)) { fail(file, "a backup case needs exactly one of base / raw"); return null; }
  if ("raw" in input) return input.raw;
  let doc;
  try { doc = JSON.parse(readFileSync(join(SPEC, input.base), "utf8")); }
  catch (e) { fail(file, `base ${input.base}: ${e.message}`); return null; }
  for (const p of input.remove ?? []) {
    const parts = pointerParts(p), last = parts.pop();
    const parent = parts.reduce((o, k) => o?.[k], doc);
    if (!parent || !(last in parent)) fail(file, `remove ${p}: no such member`); else delete parent[last];
  }
  for (const [p, v] of Object.entries(input.set ?? {})) {
    const parts = pointerParts(p), last = parts.pop();
    const parent = parts.reduce((o, k) => o?.[k], doc);
    if (parent === undefined || parent === null) fail(file, `set ${p}: no parent`); else parent[last] = v;
  }
  return JSON.stringify(doc);
}
function referenceValidate(text, appSchemaVersion) {
  let b;
  try { b = JSON.parse(text); } catch { return { error: "not_json" }; }
  if (b === null || typeof b !== "object" || Array.isArray(b)) return { error: "not_json" };
  if (b.format !== "invoicebuilder-backup") return { error: "not_a_backup" };
  if (!Number.isInteger(b.formatVersion) || b.formatVersion < 1) return { error: "not_a_backup" };
  if (b.formatVersion > 1) return { error: "newer_format" };
  if (!Number.isInteger(b.dbSchemaVersion) || b.dbSchemaVersion < 1) return { error: "invalid_record" };
  if (b.dbSchemaVersion > appSchemaVersion) return { error: "newer_schema" };
  for (const c of COLLECTIONS) {
    if (!Array.isArray(b.data?.[c])) return { error: "invalid_record" };
    const v = ajv.getSchema(`domain.schema.json#/$defs/${DOMAIN_DEF[c]}`);
    for (const r of b.data[c]) {
      // unknown keys are ignored (§3 check 5), so only errors other than "unknown property" count
      if (!v(r) && v.errors.some((e) => !/additional|unevaluated/.test(e.keyword))) return { error: "invalid_record" };
    }
  }
  for (const c of COLLECTIONS) if (b.counts?.[c] !== b.data[c].length) return { error: "count_mismatch" };
  for (const c of COLLECTIONS) if (new Set(b.data[c].map((r) => r.id)).size !== b.data[c].length) return { error: "duplicate_id" };
  for (const d of b.data.documents) if (new Set(d.lines.map((l) => l.id)).size !== d.lines.length) return { error: "duplicate_id" };
  for (const a of b.data.assets)
    if (createHash("sha256").update(Buffer.from(a.dataBase64, "base64")).digest("hex") !== a.sha256) return { error: "asset_hash_mismatch" };
  const ids = Object.fromEntries(COLLECTIONS.map((c) => [c, new Set(b.data[c].map((r) => r.id))]));
  const ok = (value, c) => value == null || ids[c].has(value);
  const refs = [
    ...COLLECTIONS.filter((c) => c !== "businesses").flatMap((c) => b.data[c].map((r) => ok(r.businessId, "businesses"))),
    ...b.data.businesses.flatMap((r) => [ok(r.logoAssetId, "assets"), ok(r.signatureAssetId, "assets")]),
    ...b.data.documents.flatMap((d) => [ok(d.clientId, "clients"), ok(d.seriesId, "numberingSeries"),
      ok(d.convertedFromId, "documents"), ...d.lines.map((l) => ok(l.catalogItemId, "catalogItems"))]),
    ...b.data.payments.map((p) => ok(p.documentId, "documents")),
  ];
  if (refs.includes(false)) return { error: "dangling_reference" };
  return { live: Object.fromEntries(COLLECTIONS.map((c) => [c, b.data[c].filter((r) => r.deletedAt == null).length])) };
}
for (const f of walk(join(SPEC, "fixtures"))) {
  const doc = readJSON(f); if (!doc) continue;
  if (!validateWith("fixtures.schema.json", doc, f)) continue;
  counts[doc.kind] = (counts[doc.kind] ?? 0) + doc.cases.length;
  for (const c of doc.cases) {
    if (seen.has(c.id)) fail(f, `duplicate case id ${c.id} (also in ${seen.get(c.id)})`);
    seen.set(c.id, relative(SPEC, f));
    if (doc.kind === "tax") checkTaxCase(f, c);
    if ((doc.kind === "validation" || doc.kind === "document") && !configs[c.input.config])
      fail(f, `case ${c.id}: unknown config ${c.input.config}`);
    if (doc.kind === "pdf") {
      const ref = c.input.document.taxConfigRef;
      if (!configs[ref]) fail(f, `case ${c.id}: unknown config ${ref}`);
      if (!layouts.some(([, layout]) => layout.id === c.input.template))
        fail(f, `case ${c.id}: no layout for template "${c.input.template}"`);
    }
    if (doc.kind === "backup") {
      const text = patchBackup(f, c.input);
      if (text !== null) {
        const actual = referenceValidate(text, c.input.appSchemaVersion);
        if (JSON.stringify(actual) !== JSON.stringify(c.expected))
          fail(f, `case ${c.id}: the reference gives ${JSON.stringify(actual)}, expected ${JSON.stringify(c.expected)}`);
      }
    }
    if (doc.kind === "input" && c.input.op === "money" && !currencyCodes.has(c.input.currency))
      fail(f, `case ${c.id}: money input needs a currency from reference/currencies.json`);
  }
}

// ---------- samples (portable backups) ----------
const samplesDir = join(SPEC, "samples");
let sampleCount = 0;
for (const f of (statSync(samplesDir, { throwIfNoEntry: false }) ? walk(samplesDir) : [])) {
  const b = readJSON(f); if (!b || !validateWith("backup.schema.json", b, f)) continue;
  sampleCount++;
  for (const [k, n] of Object.entries(b.counts)) if (b.data[k].length !== n) fail(f, `counts.${k} = ${n} but data.${k} has ${b.data[k].length}`);
  for (const a of b.data.assets)
    if (createHash("sha256").update(Buffer.from(a.dataBase64, "base64")).digest("hex") !== a.sha256) fail(f, `asset ${a.id} sha256 mismatch`);
  for (const biz of b.data.businesses) if (!configFamilies.has(biz.taxConfig)) fail(f, `business ${biz.id}: unknown taxConfig ${biz.taxConfig}`);
  for (const d of b.data.documents) if (!configs[d.taxConfigRef]) fail(f, `document ${d.id}: unknown taxConfigRef ${d.taxConfigRef}`);
}

// ---------- database schema ----------
const LOCAL_TABLES = new Set(["device_state", "app_state"]);     // this device only: never synced, never backed up
const RESERVED_COLUMNS = new Set(["creationdate", "creatoruserrecordid", "etag", "lastmodifieduserrecordid",
  "modificationdate", "modifiedbydevice", "recordchangetag", "recordid", "recordtype"]); // CloudKit-reserved keys
const ALLOWED_ON_DELETE = new Set(["CASCADE", "SET NULL", "SET DEFAULT"]); // RESTRICT / NO ACTION break SyncEngine
const dbDir = join(schemaDir, "db");
const schemaFile = join(dbDir, "schema.sql");
const migrationFiles = readdirSync(join(dbDir, "migrations")).filter((f) => /^\d{4}_.+\.sql$/.test(f)).sort();
migrationFiles.forEach((f, i) => {
  if (Number(f.slice(0, 4)) !== i + 1) fail(join(dbDir, "migrations", f), "migration numbers must be contiguous from 0001");
});
const INTROSPECT = `.mode json
SELECT m.name AS name, m.sql AS sql,
  json((SELECT json_group_array(json_array(c.name, c.type, c."notnull", c.dflt_value, c.pk, c.hidden))
        FROM pragma_table_xinfo(m.name) AS c)) AS columns,
  json((SELECT json_group_array(json_array(k."table", k."from", k."to", k.on_update, k.on_delete))
        FROM pragma_foreign_key_list(m.name) AS k)) AS foreignKeys,
  json((SELECT json_group_array(json_array(i.name, i."unique", i.origin, i.partial,
          json((SELECT json_group_array(x.name) FROM pragma_index_info(i.name) AS x))))
        FROM pragma_index_list(m.name) AS i)) AS indexes
FROM sqlite_master AS m WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%' ORDER BY m.name;`;
function introspect(sql, file) {
  const r = spawnSync("sqlite3", ["-bail", ":memory:"], { input: `${sql}\n;\n${INTROSPECT}\n`, encoding: "utf8" });
  if (r.error) { fail(dbDir, "the sqlite3 CLI is required (macOS: built in; Debian/Ubuntu: apt-get install sqlite3)"); return null; }
  if (r.status !== 0 || r.stderr.trim()) { fail(file, `SQL error: ${(r.stderr || `exit ${r.status}`).trim()}`); return null; }
  const parse = (v) => (typeof v === "string" ? JSON.parse(v) : v ?? []);
  return Object.fromEntries(JSON.parse(r.stdout || "[]").map((t) => [t.name,
    { sql: t.sql, columns: parse(t.columns), foreignKeys: parse(t.foreignKeys), indexes: parse(t.indexes) }]));
}
const stripComments = (sql) => sql.replace(/--[^\n]*/g, "");
function checkClauses(sql) { // every CHECK (...) with balanced parentheses, comments stripped, whitespace normalised
  const s = stripComments(sql), out = [];
  for (const m of s.matchAll(/\bCHECK\s*\(/gi)) {
    let depth = 0;
    for (let j = m.index + m[0].length - 1; j < s.length; j++) {
      if (s[j] === "(") depth++;
      else if (s[j] === ")" && --depth === 0) { out.push(s.slice(m.index, j + 1).replace(/\s+/g, " ")); break; }
    }
  }
  return out.sort();
}
const shape = (t) => ({
  columns: t.columns, // ordered: new columns go at the end of their table, as ALTER TABLE ADD COLUMN does
  foreignKeys: t.foreignKeys.map((k) => JSON.stringify(k)).sort(),
  indexes: t.indexes.map((i) => JSON.stringify(i)).sort(),
  checks: checkClauses(t.sql),
});
const fromSchema = introspect(readFileSync(schemaFile, "utf8"), schemaFile);
const fromMigrations = introspect(
  migrationFiles.map((f) => readFileSync(join(dbDir, "migrations", f), "utf8")).join("\n;\n"), join(dbDir, "migrations"));
if (fromSchema && fromMigrations) {
  for (const name of new Set([...Object.keys(fromSchema), ...Object.keys(fromMigrations)])) {
    const a = fromSchema[name], b = fromMigrations[name];
    if (!a || !b) { fail(schemaFile, `table ${name} exists only in ${a ? "schema.sql" : "the migrations"}`); continue; }
    const sa = shape(a), sb = shape(b);
    for (const k of Object.keys(sa)) if (JSON.stringify(sa[k]) !== JSON.stringify(sb[k]))
      fail(schemaFile, `table ${name}: ${k} differ from the result of applying all migrations in order`);
  }
  for (const [name, t] of Object.entries(fromSchema)) {
    if (LOCAL_TABLES.has(name)) continue;
    const pks = t.columns.filter((c) => c[4] > 0);
    if (pks.length !== 1 || !/^TEXT$/i.test(pks[0][1]) || pks[0][2] !== 1)
      fail(schemaFile, `table ${name}: needs exactly one TEXT NOT NULL primary key column`);
    else if (!new RegExp(`\\b${pks[0][0]}\\s+TEXT\\s+PRIMARY\\s+KEY\\s+NOT\\s+NULL\\s+ON\\s+CONFLICT\\s+REPLACE\\b`, "i")
      .test(stripComments(t.sql)))
      fail(schemaFile, `table ${name}: primary key must be declared "TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE"`);
    for (const [index, unique, origin] of t.indexes)
      if (unique && origin !== "pk") fail(schemaFile, `table ${name}: UNIQUE ${origin === "c" ? "index" : "constraint"} ${index} is not allowed on synced tables`);
    for (const [target, from, , , onDelete] of t.foreignKeys)
      if (!ALLOWED_ON_DELETE.has(onDelete))
        fail(schemaFile, `table ${name}: foreign key ${from} → ${target} needs ON DELETE CASCADE, SET NULL or SET DEFAULT (has ${onDelete})`);
    for (const [column] of t.columns)
      if (RESERVED_COLUMNS.has(column.toLowerCase())) fail(schemaFile, `table ${name}: column ${column} is a CloudKit reserved name`);
    for (const check of checkClauses(t.sql))
      if (/\bIN\s*\([^)]*'/i.test(check))
        fail(schemaFile, `table ${name}: value-list ${check} is not allowed on synced tables — enforce the values in app code`);
  }
  // SyncEngine rejects reference cycles, a table referencing itself included ("cycleDetected").
  const edges = Object.fromEntries(Object.entries(fromSchema).filter(([n]) => !LOCAL_TABLES.has(n))
    .map(([n, t]) => [n, [...new Set(t.foreignKeys.map((k) => k[0]))]]));
  const visiting = new Set(), done = new Set();
  const visit = (n, path) => {
    if (done.has(n)) return;
    if (visiting.has(n)) { fail(schemaFile, `foreign keys form a cycle: ${[...path, n].join(" → ")} (SyncEngine rejects cycles)`); return; }
    visiting.add(n);
    for (const m of edges[n] ?? []) visit(m, [...path, n]);
    visiting.delete(n); done.add(n);
  };
  for (const n of Object.keys(edges)) visit(n, []);
}

// ---------- report ----------
if (errors.length) {
  console.error(`✗ spec validation failed (${errors.length} problem${errors.length === 1 ? "" : "s"}):`);
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}
const total = Object.values(counts).reduce((a, b) => a + b, 0);
const tableCount = fromSchema ? Object.keys(fromSchema).length : 0;
console.log(`✓ spec valid: ${Object.keys(configs).length} tax configs, ${layouts.length} PDF templates, ${currencies.length} currencies, ${countries.length} countries, ${units.length} units`);
console.log(`✓ database: ${tableCount} tables; schema.sql matches ${migrationFiles.length} migration(s) structurally; sync-safe rules hold; ${sampleCount} backup sample(s) valid`);
console.log(`✓ fixtures: ${total} cases (${Object.entries(counts).map(([k, v]) => `${k} ${v}`).join(", ") || "none yet"})`);
