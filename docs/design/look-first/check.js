const fs = require('fs');
const path = require('path');
const dir = path.join(__dirname, 'prototype');

function load(file) {
  const src = fs.readFileSync(path.join(dir, file), 'utf8');
  const script = src.match(/<script type="text\/x-dc"[^>]*>([\s\S]*?)<\/script>/)[1];
  const markup = src.match(/<x-dc>([\s\S]*?)<\/x-dc>/)[1];
  const DCLogic = class { constructor(props) { this.props = props || {}; this.state = null; } setState(p) { this.state = Object.assign({}, this.state, p); } };
  const Component = new Function('DCLogic', script + '\nreturn Component;')(DCLogic);
  return { Component, markup };
}

// every {{ hole }} must resolve against renderVals (loop aliases resolved from their list's first item)
function checkHoles(markup, vals, label) {
  const problems = [];
  const aliases = {};
  const forRe = /<sc-for list="\{\{\s*([\w.]+)\s*\}\}" as="(\w+)"/g;
  let m;
  while ((m = forRe.exec(markup))) aliases[m[2]] = m[1];
  const get = (p) => {
    const parts = p.split('.');
    let root;
    if (aliases[parts[0]] !== undefined) {
      const list = get(aliases[parts[0]]);
      if (!Array.isArray(list)) return { missing: true, why: 'list ' + aliases[parts[0]] + ' not array' };
      if (!list.length) return { skip: true };
      root = list[0];
    } else root = vals[parts[0]];
    if (root === undefined) return { missing: true, why: parts[0] };
    let cur = root;
    for (const k of parts.slice(1)) { if (cur == null || cur[k] === undefined) return { missing: true, why: p }; cur = cur[k]; }
    return cur;
  };
  const holeRe = /\{\{\s*([^}]+?)\s*\}\}/g;
  while ((m = holeRe.exec(markup))) {
    const p = m[1];
    if (/^(true|false|\d+)$/.test(p) || p === '$index') continue;
    if (!/^[\w$.]+$/.test(p)) { problems.push('not a dotted lookup: ' + p); continue; }
    const r = get(p);
    if (r && r.missing) problems.push('unresolved: ' + p + ' (' + r.why + ')');
  }
  if (problems.length) console.log('HOLES', label, [...new Set(problems)]);
  return problems.length;
}

let fails = 0;
const inv = load('Invoice.dc.html');
for (const t of ['modern', 'classic', 'minimal', 'compact']) {
  const c = new inv.Component({ template: t });
  fails += checkHoles(inv.markup, c.renderVals(), 'Invoice ' + t);
}

const main = load('Main.dc.html');
const starts = ['welcome', 'look', 'name', 'address', 'tax', 'client', 'items', 'when', 'pay', 'review', 'sent', 'home', 'repeat'];
for (const country of ['India', 'UK']) for (const registered of [true, false]) for (const start of starts) {
  const c = new main.Component({ start, country, registered });
  let v;
  try { v = c.renderVals(); } catch (e) { console.log('THROW', country, registered, start, e.message); fails++; continue; }
  // screen-specific holes only matter where shown; check all anyway but on a representative state
  fails += checkHoles(main.markup, v, [country, registered, start].join('/'));
  // the invoice each screen passes down must render
  for (const t of ['modern', 'classic', 'minimal', 'compact']) {
    const ic = new inv.Component({ template: t, inv: v.inv, focus: v.pv.focus, accent: '#0F766E' });
    try { fails += checkHoles(inv.markup, ic.renderVals(), 'Invoice from ' + start + ' ' + t); } catch (e) { console.log('INV THROW', start, t, e.message); fails++; }
  }
}

// drive a first-run flow through the handlers, as a tester would
function flow(country, gst) {
  const c = new main.Component({ country });
  const on = () => c.renderVals().on;
  const ev = (v) => ({ target: { value: v } });
  const screen = () => c.st().screen;
  const log = [];
  on().start(); log.push(screen());
  on().next(); log.push(screen());
  on().bizName(ev('Asha Designs'));
  if (!c.canNext(c.st())) throw new Error('name blocked');
  on().next(); log.push(screen());
  on().bizLine1(ev('14 Main Road'));
  if (country === 'India') { if (c.canNext(c.st())) throw new Error('address allowed without state'); c.up({ sheet: 'state', stateFor: 'biz' }); c.renderVals().stateList.find((x) => x.name === 'Karnataka').pick(); }
  on().next(); log.push(screen());
  if (gst) { on().taxYes(); on().taxId(ev(country === 'India' ? '29abcde1234f1z5' : '123456789')); } else on().taxNo();
  if (!c.canNext(c.st())) throw new Error('tax blocked: ' + c.st().taxId);
  on().next(); log.push(screen());
  on().clientName(ev('Ravi'));
  on().next(); log.push(screen());
  on().dName(ev('Logo design')); on().qtyPlus(); on().dPrice(ev(country === 'India' ? '2,500' : '250'));
  const lineText = c.renderVals().it.lineText;
  on().next(); log.push(screen());
  c.renderVals().wn.opts[1].pick();
  on().next(); log.push(screen());
  on().next(); log.push(screen());
  const v = c.renderVals();
  const out = { flow: log.join(' > '), lineText, title: v.inv.title, totals: v.inv.totals.map((x) => x.k + ' ' + x.v), total: v.rv.total, lock: v.rv.lock, send: v.rv.sendLabel };
  on().send();
  const v2 = c.renderVals();
  out.sent = v2.sn.title + ' | ' + v2.sn.sub;
  on().another();
  out.repeat = c.renderVals().hd.label + ' | recent: ' + c.renderVals().cl.recent.map((r) => r.name).join(', ');
  return out;
}
for (const [country, gst] of [['India', true], ['India', false], ['UK', true], ['UK', false]]) {
  try { console.log(country, gst ? 'registered' : 'not registered', JSON.stringify(flow(country, gst), null, 1)); } catch (e) { console.log('FLOW FAIL', country, gst, e.stack); fails++; }
}

// inter-state IGST, composition, inclusive price
{
  const c = new main.Component({ start: 'review', country: 'India', registered: true });
  c.up({ client: Object.assign({}, c.st().client, { region: '33' }) });
  console.log('IGST:', c.renderVals().inv.totals.map((x) => x.k + ' ' + x.v).join(' | '));
  c.up({ includesTax: true, client: Object.assign({}, c.st().client, { region: '' }) });
  console.log('Inclusive:', c.renderVals().inv.totals.map((x) => x.k + ' ' + x.v).join(' | '), '| total', c.renderVals().inv.total.v);
  c.up({ includesTax: false, scheme: 'composition' });
  const v = c.renderVals();
  console.log('Composition:', v.inv.title, '|', v.inv.note, '|', v.inv.totals.map((x) => x.k).join(','), '| total', v.inv.total.v, '| rates shown:', v.it.charges);
}
console.log(fails ? 'FAILURES: ' + fails : 'ALL CHECKS PASSED');
