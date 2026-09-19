// Renders every view model through the shared HTML template in headless Chromium (Blink = Android WebView's engine)
// and records timing, page count and file size. Usage: node render-chromium.mjs
import { chromium } from "playwright";
import { readFileSync, readdirSync, writeFileSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const templateUrl = pathToFileURL(join(here, "template/template.html")).href;
const browser = await chromium.launch();
const results = [];
for (const file of readdirSync(join(here, "viewmodels")).filter((f) => f.endsWith(".json")).sort()) {
  const vm = JSON.parse(readFileSync(join(here, "viewmodels", file), "utf8"));
  const page = await browser.newPage();
  const t0 = performance.now();
  await page.goto(templateUrl);
  await page.evaluate((m) => window.renderInvoice(m), vm);
  const t1 = performance.now();
  const pdf = await page.pdf({ preferCSSPageSize: true, printBackground: true });
  const t2 = performance.now();
  const out = join(here, "out", file.replace(".json", ".chromium.pdf"));
  writeFileSync(out, pdf);
  const pages = (pdf.toString("latin1").match(/\/Type\s*\/Page[^s]/g) || []).length;
  results.push({ doc: file.replace(".json", ""), renderMs: Math.round(t1 - t0), pdfMs: Math.round(t2 - t1), pages, kb: Math.round(statSync(out).size / 1024) });
  await page.close();
}
await browser.close();
console.table(results);
writeFileSync(join(here, "out/chromium-results.json"), JSON.stringify(results, null, 2));
