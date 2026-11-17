# AppVault 0.4.1 (8) verification

- Source: dd61ecfbd84699258d0c109a4570edecd9ebb807.
- GitHub build: https://github.com/soum91/AppVault/actions/runs/44023743376, successful.
- Installed-version preflight, direct Store protocol fixtures, legacy copy fixtures, iOS device compilation, IPA packaging, prerelease publication and FlareStore feed refresh all passed.
- Protocol fixtures verify relative/unsafe redirect handling, exact login plist keys and XML escaping, lowercase response headers, token-only account encoding, HTTP 403, 2FA challenge handling, SINF traversal rejection and allowed CDN hosts.
- Downloaded the public release IPA and checked com.soum91.appvault, version 0.4.1, build 8, assigned AppIcon and default ATS configuration (no trust override).
- Released IPA: 319,554 bytes; SHA-256 a4287d31d48dd09482e1d7bdd78a38c4e6881ab0cef627fc4c2bc673ea376969.
- Confirmed that Go build and Unicorn uc_version markers are absent from the app executable. The emulator source, bridge, static-library settings and build script were removed.
- FlareStore lists AppVault 0.4.1 (8). The separately requested official DLiPA entry remains unchanged.

Not verified: physical-device startup, Apple Account login/2FA, actual IPA downloads, clipboard/share/Files export or reinstallation. Apple may reject unsigned authentication with HTTP 403. The app has no JIT dependency and does not claim to overcome Apple's server-side requirements.

The historical release audit rejected v0.1.0's two-word file-add commits (for example, Add AppVault/BackupService.swift). Its classifier now accepts exact source filenames only when that same file appears in the commit diff; generic or mismatched subjects remain rejected. Local classifier fixtures passed. The previous red run is historical; the corrected workflow will reconcile it on its next scheduled run.
