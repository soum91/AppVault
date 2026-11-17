# AppVault 0.4.0 (7) experimental integration

- Source commit: ce59f077ce6ad3e18ffe91261b60fc4159e8dbb0.
- GitHub iOS build passed: https://github.com/soum91/AppVault/actions/runs/44021717841.
- ipatool pin: b352566155a667d8aaeabaa7ecec4966080f92ab.
- Checked packaged bundle: com.soum91.appvault, version 0.4.0, build 7. AppIcon asset is assigned and both ipatool and Unicorn notices are bundled.
- Inspected arm64 executable: AVIPARun, AVIPAStatus, uc_open and uc_version are linked. This is an embedded backend, not an external-app shortcut.
- IPA SHA-256: d1af6d091450fe0b19ecedb49671677c1cc098774b9e77cec8bd3cbbace774bf (17,372,840 bytes).
- Host Go tests with race detector passed: password removal, credential clearing, error redaction and cookie persistence/deletion. The last cookie fixture was added after the device build; it does not change packaged app source.
- Installed-version preflight and existing legacy data-copy fixtures passed in CI.

Not verified: physical-device startup, JIT access, real Apple Account authentication/2FA, IPA download, clipboard/share/Files export or package reinstallation. Executable-memory permission is a prerequisite, not a proof of runtime compatibility. Stock iOS without JIT cannot use this pinned authentication engine. Do not describe the build as a working login fix.

The FlareStore feed remains on its prior published app version. This experimental integration is available as the workflow artifact and is not automatically promoted to a release.
