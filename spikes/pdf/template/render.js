// Shared invoice renderer for the PDF spike (Option A). Plain ES2019, no dependencies, so it runs unchanged in
// WKWebView (iOS), Android WebView and desktop browsers. The native side passes a fully pre-formatted view model;
// this script only builds DOM. Returns a Promise that resolves once fonts and images are ready to print.
(function () {
  "use strict";
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined && text !== null) e.textContent = text;
    return e;
  }
  function kv(list, cls) {
    var box = el("dl", cls);
    (list || []).forEach(function (item) {
      box.appendChild(el("dt", null, item.label));
      box.appendChild(el("dd", null, item.value));
    });
    return box;
  }
  function party(title, p) {
    var box = el("section", "party");
    box.appendChild(el("h3", null, title));
    box.appendChild(el("p", "party-name", p.name));
    (p.lines || []).forEach(function (l) { box.appendChild(el("p", null, l)); });
    if (p.ids && p.ids.length) box.appendChild(kv(p.ids, "ids"));
    return box;
  }
  function img(src, cls, alt) {
    var i = el("img", cls); i.src = src; i.alt = alt || ""; return i;
  }

  window.renderInvoice = function (vm) {
    var root = document.getElementById("invoice");
    root.innerHTML = "";
    document.documentElement.style.setProperty("--accent", vm.accent || "#1F6FEB");

    (vm.topNotes || []).forEach(function (n) { root.appendChild(el("p", "top-note", n)); });

    var header = el("header", "doc-header");
    var brand = el("div", "brand");
    if (vm.seller.logo) brand.appendChild(img(vm.seller.logo, "logo", vm.seller.name));
    var who = el("div", "seller");
    who.appendChild(el("h1", null, vm.seller.name));
    (vm.seller.lines || []).forEach(function (l) { who.appendChild(el("p", null, l)); });
    if (vm.seller.ids && vm.seller.ids.length) who.appendChild(kv(vm.seller.ids, "ids"));
    brand.appendChild(who);
    header.appendChild(brand);
    var titleBox = el("div", "title-box");
    titleBox.appendChild(el("h2", "doc-title", vm.title));
    if (vm.draft) titleBox.appendChild(el("p", "draft-badge", "DRAFT"));
    titleBox.appendChild(kv(vm.meta, "meta"));
    header.appendChild(titleBox);
    root.appendChild(header);

    var parties = el("div", "parties");
    parties.appendChild(party("Bill to", vm.billTo));
    if (vm.shipTo) parties.appendChild(party("Ship to", vm.shipTo));
    root.appendChild(parties);

    var table = el("table", "items");
    var thead = el("thead"), hr = el("tr");
    vm.columns.forEach(function (c) { var th = el("th", c.align === "right" ? "num" : "", c.label); th.dataset.key = c.key; hr.appendChild(th); });
    thead.appendChild(hr); table.appendChild(thead);
    var tbody = el("tbody");
    vm.rows.forEach(function (r) {
      var tr = el("tr");
      vm.columns.forEach(function (c) {
        var td = el("td", c.align === "right" ? "num" : "");
        td.dataset.key = c.key;
        td.appendChild(document.createTextNode(r[c.key] || ""));
        if (c.key === "description" && r.sub) td.appendChild(el("div", "sub", r.sub));
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    root.appendChild(table);

    var summary = el("div", "summary");
    var left = el("div", "summary-left");
    if (vm.amountInWords) { left.appendChild(el("h3", null, "Amount in words")); left.appendChild(el("p", "words", vm.amountInWords)); }
    if (vm.home) left.appendChild(el("p", "home", vm.home));
    summary.appendChild(left);
    var totals = el("table", "totals");
    vm.totals.forEach(function (t) {
      var tr = el("tr", t.emphasis ? "grand" : "");
      tr.appendChild(el("th", null, t.label)); tr.appendChild(el("td", "num", t.value));
      totals.appendChild(tr);
    });
    summary.appendChild(totals);
    root.appendChild(summary);

    var pay = el("div", "payment");
    if (vm.payment && vm.payment.bank) { var b = el("section", "bank"); b.appendChild(el("h3", null, "Bank details")); b.appendChild(kv(vm.payment.bank, "ids")); pay.appendChild(b); }
    if (vm.payment && vm.payment.upi) {
      var u = el("section", "upi");
      u.appendChild(img(vm.payment.upi.qr, "qr", "UPI QR code"));
      u.appendChild(el("p", "caption", vm.payment.upi.caption));
      u.appendChild(el("p", "upi-id", vm.payment.upi.id));
      pay.appendChild(u);
    }
    if (vm.signature) {
      var s = el("section", "signature");
      s.appendChild(el("p", "for", vm.signature.for));
      if (vm.signature.image) s.appendChild(img(vm.signature.image, "sign", "Signature"));
      s.appendChild(el("p", "sign-label", vm.signature.label));
      pay.appendChild(s);
    }
    root.appendChild(pay);

    if (vm.notes) { var n = el("section", "notes"); n.appendChild(el("h3", null, "Notes")); n.appendChild(el("p", null, vm.notes)); root.appendChild(n); }
    if (vm.terms) { var t2 = el("section", "notes"); t2.appendChild(el("h3", null, "Terms and conditions")); t2.appendChild(el("p", null, vm.terms)); root.appendChild(t2); }
    (vm.bottomNotes || []).forEach(function (x) { root.appendChild(el("p", "bottom-note", x)); });

    var images = Array.prototype.slice.call(document.images).map(function (i) {
      return i.decode ? i.decode().catch(function () {}) : Promise.resolve();
    });
    return Promise.all(images.concat([document.fonts ? document.fonts.ready : Promise.resolve()])).then(function () {
      document.body.dataset.ready = "true";
      return true;
    });
  };
})();
