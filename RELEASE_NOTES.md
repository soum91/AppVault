# AppVault 0.6.9 (22): enable JavaScriptCore WebAssembly on the rootless DEB

The 0.6.8 Backend Report from Dopamine/iOS 16.1.1 showed: `dynamic-codesigning` true at runtime, code-signing flags `VALID, ENFORCEMENT, PLATFORM_BINARY, DEBUGGED`, a `MAP_JIT` probe failing with EINVAL (consistent with JavaScriptCore already holding the process's single JIT region), JavaScriptCore `WebAssembly=undefined`, and no WebContent crash or jetsam reports. JIT is granted, but JavaScriptCore's own options left WebAssembly off.

Changes:
- `AppVault/AppVaultApp.swift`: on rootless installs only, set `JSC_useJIT=true` and `JSC_useWebAssembly=true` in the environment at app launch, before any JSContext exists, so JavaScriptCore enables WebAssembly for the in-process signer. The sideloaded IPA is unaffected.
- Backend Report shows the two `JSC_*` values and explains a `MAP_JIT` EINVAL result.

**Verification boundary:** CI builds both packages. Whether JavaScriptCore on iOS 16.1.1 honours these environment options for this app has not been confirmed on a device; check the `JavaScriptCore:` line in Settings > Backend Report.
