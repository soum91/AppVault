# AppVault 0.7.1 (24)

On the reported Dopamine iOS 16.1.1 device, both JavaScriptCore processes had native WebAssembly unavailable and WebKit exited before the Apple login request. The rootless signer now falls back to a C WebAssembly interpreter when native WebAssembly is unavailable. The normal Apple account and verification flow runs in the same AppVault app.

The bridge loads the pinned Go signer and Unicorn modules, including their typed imports, exports, indirect calls and growing linear memory. The interpreter uses ordinary writable memory and disables Unicorn’s optional fragment JIT. The package build runs the production JavaScriptCore bridge with native WebAssembly disabled and checks that both modules and the local Store runtime initialize. No account credentials are used in that test.

A physical Dopamine iPhone is still needed to verify Apple sign-in, trusted-device approval and a completed download.
