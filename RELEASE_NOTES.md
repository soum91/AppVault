# AppVault 0.6.4 (17): iOS 16 WebKit runtime survival and diagnostics

The 0.6.3 jailbreak device reported **Apple authentication runtime could not complete** before an Apple Store login response. In current source, this generic alert can mask a WebKit WebContent process termination during the embedded SAP WebAssembly engine.

Changes:
- Replace the almost invisible 1×1 WebKit authentication view with a real, foreground, 140-point signing view in a temporary AppVault overlay. The upstream runtime HTML is deliberately blank; it only hosts the local signing scripts. This keeps the actual WebKit view attached and visible while the heavy runtime is executing.
- Fix a concrete lifecycle problem: AppVault previously reset its local signing/proxy listener unconditionally on **memory warning**, even while signing was underway. Preserve the active listener; clean up idle instances only.
- Emit a distinct `WEB_CONTENT_EXIT` failure when iOS terminates the WebContent process. Record bounded, credentials-free runtime steps (asset loading, loopback readiness, page navigation, JavaScript execution, WebKit exit) in **Settings > Backend Report**.
- Retain the existing manual Apple Account six-digit verification code, Apple-issued approval handling, signed Store requests, pinned runtime hashes, private storage, rootless decryption and export paths.

**Verification boundary:** The Python regression checks, Apple Store fixtures and native GitHub CI build must pass before publication. Neither the previous device screenshot nor CI can conclusively prove that the WebContent process was killed by memory pressure. A successful Apple Account login or decrypted export on Dopamine/iOS 16.1.1 remains unverified until tested on the physical device. This release does not bypass 2FA or change Apple's Store authentication endpoints.
