# AppVault 0.7.1 (24): wasm3 interpreter polyfill for rootless DEB login

0.7.0's out-of-process signer helper did not fix rootless sign-in. Dopamine's forkfix.dylib is injected into every process, not just UIKit apps: it claims the single MAP_JIT region before JavaScriptCore can, disabling JIT and WebAssembly in both the app and the standalone helper. No amount of entitlements or process isolation can reclaim it.

This release takes a fundamentally different approach: instead of trying to get native WebAssembly working, it embeds wasm3, a pure C WebAssembly interpreter that needs no JIT, MAP_JIT, or dynamic-codesigning entitlement.

Changes:
- Vendored wasm3 v0.9.2 (MIT license) as pure C source in `AppVault/Wasm3/`. Interprets WASM bytecode directly without compiling to native code.
- New `Wasm3Polyfill.swift` installs a complete `WebAssembly` global object (instantiate, Memory, Module, Instance) into the JSContext using wasm3 as the backend. The polyfill uses a C trampoline system so WASM module imports call back into the JavaScript import functions correctly.
- `InProcessSAPRuntime.setUp()` now detects when native WebAssembly is unavailable and injects the wasm3 polyfill automatically, instead of throwing `webAssemblyUnavailable` and falling through to the broken WebKit path.
- The existing JavaScript runtime (wasm_exec.js, sap-signer.js, sap.wasm) works unchanged. The polyfill provides the same WebAssembly API surface that the Go WASM runtime expects.
- The signer helper binary also includes the wasm3 polyfill, compiled from the same C sources.
- CI compiles the wasm3 C sources for arm64 iOS 16 as part of both the xcodebuild and the standalone helper build.

Performance note: the wasm3 interpreter is slower than JIT-compiled WebAssembly (the SAP signing step may take 30-60 seconds instead of 10-15). This runs once per sign-in attempt.

**Verification boundary:** CI builds both packages with the wasm3 polyfill compiled. The polyfill installs correctly when native WebAssembly is detected as unavailable. Actual rootless device sign-in remains unverified pending a signed-device test.
