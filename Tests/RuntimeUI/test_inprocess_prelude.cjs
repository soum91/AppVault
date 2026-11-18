#!/usr/bin/env node
// Exercises the in-process SAP runtime's browser shims (InProcessSAPRuntime.prelude)
// in a bare V8 realm, which, like a fresh JSContext, has no URL, fetch, timers,
// TextEncoder, crypto, atob or document. Native __av* hooks are emulated here.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const swift = fs.readFileSync(path.join(__dirname, "../../AppVault/Attestation/InProcessSAPRuntime.swift"), "utf8");
const match = /static let prelude = #"""\n([\s\S]*?)"""#/.exec(swift);
assert(match, "prelude not found in InProcessSAPRuntime.swift");

const BASE = "http://127.0.0.1:4321/cap0123/runtime/index.html";
const timers = new Map(); let seq = 0;
const fetched = [];
const ctx = vm.createContext({});
const realm = vm.runInContext("globalThis", ctx);
for (const name of ["URL", "fetch", "setTimeout", "TextEncoder", "TextDecoder", "crypto", "atob", "document", "performance"]) {
  assert.strictEqual(typeof realm[name], "undefined", name + " should not exist in the bare realm");
}
const buf = b => vm.runInContext("(n => new ArrayBuffer(n))", ctx)(b.length);
const toRealm = b => { const ab = buf(b); new (vm.runInContext("Uint8Array", ctx))(ab).set(b); return ab; };
Object.assign(realm, {
  __avBaseURI: BASE,
  __avResolveURL: (input, base) => { try { return new URL(input, base === null ? undefined : base).href; } catch (_) { return ""; } },
  __avNow: () => 1,
  __avRandom: n => toRealm(require("crypto").randomBytes(n)),
  __avUTF8Encode: s => toRealm(Buffer.from(s, "utf8")),
  __avUTF8Decode: (ab, off, len) => Buffer.from(ab, off, len).toString("utf8"),
  __avSchedule: (ms, fn) => { const id = ++seq; timers.set(id, setTimeout(() => { timers.delete(id); fn(); }, ms)); return id; },
  __avCancel: id => { clearTimeout(timers.get(id)); timers.delete(id); },
  __avStage: () => {},
  __avLoadScript: url => { realm.Go = function () {}; return url === "http://127.0.0.1:4321/cap0123/runtime/wasm_exec.js"; },
  __avFetch: (url, method, headers, ab, off, len, cb) => {
    fetched.push({ url, method, headers: JSON.parse(headers), body: ab ? Buffer.from(ab, off, len).toString() : null });
    setTimeout(() => cb(url.includes("/runtime/") ? 200 : 403, toRealm(Buffer.from("ok")), "{\"Content-Type\":\"text/plain\"}", null), 0);
  }
});
vm.runInContext(match[1], ctx, { filename: "prelude.js" });
for (const hook of ["__avFetch", "__avLoadScript", "__avBaseURI"]) assert.strictEqual(realm[hook], undefined, hook + " should be removed");

const run = src => vm.runInContext(src, ctx);
assert.strictEqual(run('new URL("../proxy", new URL(".", document.baseURI).href).href'), "http://127.0.0.1:4321/cap0123/proxy");
assert.strictEqual(run('(() => { const t = new URL("http://127.0.0.1:4321/cap0123/proxy?x=1", document.baseURI); t.search = ""; t.searchParams.set("url", "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy"); return t.href; })()'),
  "http://127.0.0.1:4321/cap0123/proxy?url=https%3A%2F%2Ffpinit.itunes.apple.com%2Fv1%2FsignSapSetup%2Flegacy");
assert.throws(() => run('new URL("relative-without-base")'));
assert.strictEqual(run('new TextDecoder("utf-8").decode(new TextEncoder().encode("h\\u00e9llo \\u2713"))'), "héllo ✓");
assert.strictEqual(run('new TextDecoder().decode(new Uint8Array([0,104,105,0]).subarray(1,3))'), "hi");
assert.strictEqual(run('btoa("ab\\xff")'), Buffer.from([97, 98, 255]).toString("base64"));
assert.strictEqual(run('atob(btoa("\\x00\\x01binary\\xfe"))'), "\x00\x01binary\xfe");
assert.strictEqual(run('(() => { const a = new Uint8Array(8); crypto.getRandomValues(a.subarray(2, 6)); return a[0] === 0 && a[7] === 0; })()'), true);
assert.strictEqual(run('typeof performance.now()'), "number");

(async () => {
  const response = await run('fetch("sap.wasm", { cache: "no-store" })');
  assert.strictEqual(response.ok, true);
  assert.strictEqual(Buffer.from(await response.arrayBuffer()).toString(), "ok");
  assert.strictEqual(response.headers.get("content-type"), "text/plain");
  assert.strictEqual(fetched[0].url, "http://127.0.0.1:4321/cap0123/runtime/sap.wasm");
  await run('fetch("http://127.0.0.1:4321/cap0123/proxy?url=x", { method: "POST", headers: { "Content-Type": "application/x-plist" }, body: new Uint8Array([65, 66]) })');
  assert.deepStrictEqual(fetched[1], { url: "http://127.0.0.1:4321/cap0123/proxy?url=x", method: "POST", headers: { "Content-Type": "application/x-plist" }, body: "AB" });
  const cancelled = await run('new Promise(r => { let fired = false; const id = setTimeout(() => { fired = true; }, 5); clearTimeout(id); setTimeout(() => r(!fired), 20); })');
  assert.strictEqual(cancelled, true);
  const loaded = await run('new Promise((resolve, reject) => { const s = document.createElement("script"); s.src = "wasm_exec.js"; s.onload = () => resolve(typeof Go); s.onerror = reject; document.head.appendChild(s); })');
  assert.strictEqual(loaded, "function");
  const refused = await run('new Promise(resolve => { const s = document.createElement("script"); s.src = "https://example.com/x.js"; s.onload = () => resolve("loaded"); s.onerror = () => resolve("refused"); document.head.appendChild(s); })');
  assert.strictEqual(refused, "refused");
  run('reportStage(1); reportStage(9);');
  console.log("Passed in-process runtime prelude checks");
})().catch(error => { console.error(error); process.exit(1); });
