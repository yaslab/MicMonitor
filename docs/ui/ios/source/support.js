/*
 * support.js — docs/ui/macos/source・docs/ui/ios/source の *.dc.html をブラウザで表示するための簡易ランタイム
 *
 * Design キャンバスの本来のランタイムではなく、このフォルダのファイルを表示するために
 * 必要な機能（{{…}} の差し込み、<sc-if>、<sc-for>、<dc-import>、onClick などのイベント、
 * setState による再描画）だけを実装した互換版です。両方のフォルダに同じものを置いています。
 *
 * 開き方:
 *   - 他のファイルを読み込まない画面（Mac の Main / Settings / Card、iOS の Main / Settings）は、
 *     ファイルをダブルクリックしてブラウザで直接開けます。
 *   - 他のファイルを読み込む画面（*Light、*Paused など）は、ブラウザの制限で file:// からは
 *     読み込めないため、リポジトリのルートからローカルサーバー経由で開きます:
 *       python3 -m http.server 8000 --directory docs/ui/macos/source
 *       → http://localhost:8000/WindowLight.dc.html
 *       python3 -m http.server 8001 --directory docs/ui/ios/source
 *       → http://localhost:8001/PhoneLight.dc.html
 */
(function () {
  'use strict';

  class DCLogic {
    constructor(props) { this.props = props || {}; this.state = null; }
    setState(s) { this.state = Object.assign({}, this.state, s); if (this.__rerender) this.__rerender(); }
    forceUpdate() { if (this.__rerender) this.__rerender(); }
  }
  window.DCLogic = DCLogic;

  var WHOLE = /^\s*\{\{([^}]+)\}\}\s*$/;
  function lookup(scope, path) {
    path = path.trim();
    if (path === 'true') return true;
    if (path === 'false') return false;
    if (/^-?\d+(\.\d+)?$/.test(path)) return Number(path);
    return path.split('.').reduce(function (o, k) { return o == null ? undefined : o[k]; }, scope);
  }
  function interp(str, scope) {
    return str.replace(/\{\{([^}]+)\}\}/g, function (m, p) { var v = lookup(scope, p); return v == null ? '' : String(v); });
  }

  function compile(xdc, scriptEl) {
    var Cls = new Function('DCLogic', scriptEl.textContent + '\n;return Component;')(DCLogic);
    return { xdc: xdc, Cls: Cls };
  }

  var cache = {};
  async function getComp(name) {
    if (!cache[name]) {
      var text;
      try {
        var res = await fetch(name + '.dc.html');
        if (!res.ok) throw new Error(res.status);
        text = await res.text();
      } catch (e) {
        throw new Error(name + '.dc.html を読み込めませんでした。この画面はローカルサーバー経由で開いてください（例: python3 -m http.server 8000）。');
      }
      var doc = new DOMParser().parseFromString(text, 'text/html');
      cache[name] = compile(doc.querySelector('x-dc'), doc.querySelector('script[data-dc-script]'));
    }
    return cache[name];
  }

  var headSeen = new Set();
  function applyHelmet(helmet) {
    Array.prototype.forEach.call(helmet.childNodes, function (n) {
      if (n.nodeType !== 1) return;
      var key = n.outerHTML;
      if (headSeen.has(key)) return;
      headSeen.add(key);
      document.head.appendChild(document.importNode(n, true));
    });
  }

  async function mount(comp, props, host) {
    var inst = new comp.Cls(props);
    async function render() {
      var vals = inst.renderVals();
      var frag = document.createDocumentFragment();
      for (var ch of Array.from(comp.xdc.childNodes)) {
        if (ch.nodeName === 'HELMET') { applyHelmet(ch); continue; }
        await proc(ch, vals, frag);
      }
      host.replaceChildren(frag);
    }
    inst.__rerender = function () { render().catch(showError); };
    await render();
    if (typeof inst.componentDidMount === 'function') inst.componentDidMount();
  }

  function contentsHost() {
    var d = document.createElement('div');
    d.style.display = 'contents';
    return d;
  }

  async function proc(node, scope, parent) {
    if (node.nodeType === 3) { parent.appendChild(document.createTextNode(interp(node.textContent, scope))); return; }
    if (node.nodeType !== 1) return;
    var tag = node.nodeName.toLowerCase();

    if (tag === 'sc-if') {
      var a = node.getAttribute('value') || '';
      var m = a.match(WHOLE);
      if (m ? lookup(scope, m[1]) : a) for (var c of Array.from(node.childNodes)) await proc(c, scope, parent);
      return;
    }
    if (tag === 'sc-for') {
      var lm = (node.getAttribute('list') || '').match(WHOLE);
      var list = (lm ? lookup(scope, lm[1]) : null) || [];
      var as = node.getAttribute('as') || 'item';
      for (var i = 0; i < list.length; i++) {
        var s = Object.create(scope); s[as] = list[i]; s.$index = i;
        for (var c2 of Array.from(node.childNodes)) await proc(c2, s, parent);
      }
      return;
    }
    if (tag === 'dc-import') {
      var props = {};
      Array.prototype.forEach.call(node.attributes, function (at) {
        if (at.name === 'name' || at.name.indexOf('hint-') === 0) return;
        var key = at.name.replace(/-([a-z])/g, function (x, ch) { return ch.toUpperCase(); });
        var mm = at.value.match(WHOLE);
        props[key] = mm ? lookup(scope, mm[1]) : at.value;
      });
      var host = contentsHost();
      parent.appendChild(host);
      await mount(await getComp(node.getAttribute('name')), props, host);
      return;
    }

    var isSvg = node.namespaceURI === 'http://www.w3.org/2000/svg';
    var el = isSvg ? document.createElementNS(node.namespaceURI, node.localName) : document.createElement(tag);
    Array.prototype.forEach.call(node.attributes, function (at) {
      if (/^on/i.test(at.name)) {
        var em = at.value.match(WHOLE);
        var fn = em ? lookup(scope, em[1]) : null;
        if (typeof fn === 'function') el.addEventListener(at.name.slice(2).toLowerCase(), fn);
        return;
      }
      el.setAttribute(at.name, interp(at.value, scope));
    });
    if (tag === 'input' && el.hasAttribute('value')) el.value = el.getAttribute('value');
    for (var c3 of Array.from(node.childNodes)) await proc(c3, scope, el);
    parent.appendChild(el);
  }

  function showError(e) {
    var box = document.createElement('div');
    box.style.cssText = 'margin:16px;padding:12px 16px;border-radius:8px;background:#FDECEC;color:#8A1010;font:13px/1.6 -apple-system,sans-serif;white-space:pre-wrap';
    box.textContent = (e && e.message) ? e.message : String(e);
    document.body.prepend(box);
    console.error(e);
  }

  async function boot() {
    var xdc = document.querySelector('x-dc');
    var sc = document.querySelector('script[data-dc-script]');
    if (!xdc || !sc) return;
    var comp = compile(xdc.cloneNode(true), sc);
    var host = contentsHost();
    xdc.replaceWith(host);
    try { await mount(comp, {}, host); } catch (e) { showError(e); }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
