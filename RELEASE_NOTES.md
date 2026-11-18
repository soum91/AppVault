# AppVault 0.6.5 (18): in-process signer for the rootless DEB

The 0.6.4 Backend Report from Dopamine on iOS 16.1.1 (rootless install) showed `WEB_CONTENT_EXIT` at `webview-attaching`, before the signer page was even requested, then repeated exits after every reload. WebKit's WebContent process was terminating as soon as it was spawned for the platform-signed rootless app, so the 0.6.4 memory and visibility changes could not help.

Changes:
- New `AppVault/Attestation/InProcessSAPRuntime.swift`: the rootless DEB now runs the same pinned, hash-verified SAP runtime (`sap-signer.js`, `unicorn_x86.js`, `wasm_exec.js`, `sap.wasm`) in an in-process JavaScriptCore context on a dedicated 16 MB-stack thread. No WebContent process is involved.
- `packaging/AppVault-jailbreak.entitlements` adds `dynamic-codesigning`, which JavaScriptCore requires before it enables JIT and WebAssembly in-process. The sideloaded IPA's entitlements are unchanged and it keeps the WebKit runtime.
- A small native shim layer supplies what the runtime used from WebKit: `URL`, `fetch`, timers, `TextEncoder`/`TextDecoder`, `crypto.getRandomValues`, `performance.now`, `atob`/`btoa` and script loading. Requests are limited to the existing loopback server (runtime files and the three-endpoint Apple proxy), as before, and scripts load only from the verified runtime folder.
- If JavaScriptCore reports no WebAssembly (for example a DEB signed without the new entitlement), AppVault records `jsc-wasm-unavailable` and falls back to the WebKit runtime.
- `LocalSAPSigner` stops a cold WebKit attempt immediately when WebContent has already exited during attach, instead of continuing to navigate a dead view.
- Backend Report shows the active runtime (`in-process JavaScriptCore/WASM` or `local WebKit/WASM`) and records `jsc-runtime-starting`, `jsc-runtime-ready` and `javascript-error-jsc` stages. JavaScript errors are reduced to a type and a short fixed phrase; no URLs, tokens or request data.
- Release assets now include the build number: `AppVault-0.6.5-18.ipa` and `AppVault-0.6.5-18-rootless.deb`.
- New CI check `Tests/RuntimeUI/test_inprocess_prelude.cjs` runs the shim layer in a bare JavaScript realm. `Tests/RuntimeUI/test_runtime.py` adds source guards for the entitlement, rootless-only gating, WebKit fallback, loopback-only fetch and error sanitizing.

**Verification boundary:** The shim layer is tested in CI. The pinned runtime itself was not run under JavaScriptCore during development, and JIT acceptance of `dynamic-codesigning` on Dopamine/iOS 16.1.1 has not been confirmed on a device. Apple Account sign-in on the physical device stays unverified until tested; check Settings > Backend Report for the runtime line and stages. The sideloaded IPA's behaviour is unchanged.
