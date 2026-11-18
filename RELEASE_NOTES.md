# AppVault 0.6.7 (20): AppVault and sign-in restored to the rootless DEB

0.6.5 replaced the rootless DEB's AppVault app with a separate AppVault Decryptor app, and 0.6.6 kept that layout. This release undoes it: the DEB installs **AppVault.app** again, with Search, Account sign-in, IPA downloads, Decrypt Installed Apps and Settings, as it did through 0.6.4.

Changes:
- Remove the `AppVaultDecryptor` target, `Decryptor/` sources and `Tests/RootlessSplit/test_split.py`. `project.yml`, `.github/workflows/ios-build.yml`, `packaging/rootless/DEBIAN/*` and `AppVault/Decryption/DecryptionService.swift` return to their 0.6.4 layout, with version 0.6.7 (20).
- The DEB postinst unregisters the stale `AppVaultDecryptor.app` icon left by 0.6.5/0.6.6, then registers `AppVault.app`.
- Keep the in-process sign-in fix from 0.6.6: on rootless installs `LocalSAPSigner` runs the pinned SAP runtime with JavaScriptCore (`InProcessSAPRuntime.swift`), using the DEB's `dynamic-codesigning` entitlement, because WebKit's WebContent exits at spawn there. If JavaScriptCore reports no WebAssembly, it falls back to WebKit and records `jsc-wasm-unavailable`. The sideloaded IPA keeps WebKit sign-in.
- The `APPVAULT_ROOTLESS` compile flag is removed; rootless behaviour is chosen at runtime. During in-process signing a progress card replaces the WebKit view.
- Release assets: `AppVault-0.6.7-20.ipa` and `AppVault-0.6.7-20-rootless.deb`.

**Verification boundary:** CI covers the shim layer, the source guards and both builds. Rootless sign-in on Dopamine/iOS 16.1.1 has not been confirmed on a device; Settings > Backend Report shows the active runtime and stages.
