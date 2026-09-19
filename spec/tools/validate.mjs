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
  [/^design\/tokens\.json$/, "design-tokens.schema.json"],
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
for (const f of walk(join(SPEC, "fixtures"))) {
  const doc = readJSON(f); if (!doc) continue;
  if (!validateWith("fixtures.schema.json", doc, f)) continue;
  counts[doc.kind] = (counts[doc.kind] ?? 0) + doc.cases.length;
  for (const c of doc.cases) {
    if (seen.has(c.id)) fail(f, `duplicate case id ${c.id} (also in ${seen.get(c.id)})`);
    seen.set(c.id, relative(SPEC, f));
    if (doc.kind === "tax") checkTaxCase(f, c);
    if (doc.kind === "validation" && !configs[c.input.config]) fail(f, `case ${c.id}: unknown config ${c.input.config}`);
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
}

// ---------- report ----------
if (errors.length) {
  console.error(`✗ spec validation failed (${errors.length} problem${errors.length === 1 ? "" : "s"}):`);
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}
const total = Object.values(counts).reduce((a, b) => a + b, 0);
const tableCount = fromSchema ? Object.keys(fromSchema).length : 0;
console.log(`✓ spec valid: ${Object.keys(configs).length} tax configs, ${currencies.length} currencies, ${countries.length} countries, ${units.length} units`);
console.log(`✓ database: ${tableCount} tables; schema.sql matches ${migrationFiles.length} migration(s) structurally; sync-safe rules hold; ${sampleCount} backup sample(s) valid`);
console.log(`✓ fixtures: ${total} cases (${Object.entries(counts).map(([k, v]) => `${k} ${v}`).join(", ") || "none yet"})`);
