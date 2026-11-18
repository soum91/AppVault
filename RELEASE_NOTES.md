# AppVault 0.7.0 (23): out-of-process JavaScriptCore signer for the rootless DEB

0.6.9 did not fix rootless sign-in. Reading JavaScriptCore's iOS 16 source (safari-7614 branch) explains why: at startup JavaScriptCore reserves its JIT region with `MAP_JIT`. If that fails it sets `useJIT=false`, which also disables WebAssembly, after `JSC_*` environment options are applied. The 0.6.8 probe got EINVAL from `MAP_JIT`, which on iOS means the process's single JIT region already exists. Something in AppVault's UI process took it first, most likely code injected into UIKit apps.

Changes:
- New `appvault-signer` command-line helper inside `AppVault.app` (rootless DEB only). It links JavaScriptCore but not UIKit, is signed with `platform-application`, `dynamic-codesigning` and no-sandbox (`packaging/AppVault-signer.entitlements`), and runs the same `InProcessSAPRuntime.swift` and pinned runtime files. AppVault talks to it over newline-delimited JSON on stdin/stdout (`SignerHelperClient.swift`, `SignerSpawn.m`).
- `LocalSAPSigner` tries the helper first, then in-process JavaScriptCore, then WebKit. The helper stays warm between operations, like the in-process runtime.
- Backend Report shows `helper=ready`, `helper=WebAssembly unavailable` or `helper=failed (...)`, plus the non-system images loaded into the helper, so tweak injection is visible.
- The in-app `MAP_JIT` probe from 0.6.8 is removed: on iOS a `MAP_JIT` mapping claims the process's JIT region for good, so the probe could itself block JavaScriptCore.
- CI builds the helper with `swiftc` for arm64 iOS 16 and fails if it links UIKit or does not link JavaScriptCore.

**Verification boundary:** CI builds both packages and the helper. If Dopamine's own injection also takes the JIT region in a non-UIKit process, the helper will report `WebAssembly unavailable` with its loaded images. Rootless device sign-in has not been confirmed.
