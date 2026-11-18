# AppVault 0.6.8 (21): signer environment and WebContent crash diagnostics

The 0.6.7 Backend Report from Dopamine/iOS 16.1.1 showed `runtime=local WebKit/WASM (in-process JIT unavailable)`: JavaScriptCore reported no WebAssembly, AppVault fell back to WebKit, and WebContent exited again. The 0.6.7 DEB binary does carry `dynamic-codesigning` (checked in the released package), so the reason is on the device side. This release adds the facts needed to tell which.

Changes:
- New `AppVault/Attestation/RuntimeProbe.swift`, appended to Settings > Backend Report:
  - runtime values of the `dynamic-codesigning` and `platform-application` entitlements (SecTask);
  - code-signing flags from `csops` (VALID, PLATFORM_BINARY, DEBUGGED and others);
  - a one-page `MAP_JIT` mapping probe with errno (rootless installs only);
  - JavaScriptCore's own WebAssembly availability and a minimal module compile;
  - on rootless installs, a summary of the newest WebContent crash reports and jetsam events from the last six hours (exception, termination namespace/code/reasons, application-specific info, top frames). No account data is read.
- No sign-in logic changes. Login on the device is still expected to fail until these facts identify the blocker.

**Verification boundary:** CI builds both packages. The probes have not run on a device yet.
