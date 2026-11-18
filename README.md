## Authentication failure visibility (0.6.2)

AppVault now displays its own localized tool errors instead of `AppVaultToolError code 0` and safely labels the failing local signer/WebKit code. Use **Settings > Backend Report** to inspect the last stage without publishing your Apple Account credentials. This improves diagnosis, not Apple authentication compatibility itself.

## Authentication stage diagnostics (0.6.1)

When the Apple Account sign-in waits, AppVault shows the current authentication
phase and progress through its seven pinned runtime components. Runtime network
requests have explicit timeouts. On failure, use Settings > Backend Report for
the failing stage. These changes do not establish a successful login on a
physical iOS 16 device; do not repeatedly submit credentials when a stage stalls.

## Stock iOS helper workflow (0.6.0)

Prepare a per-app helper in **IPAs > Decrypt on Stock iOS**, sign/install with payload-preserving EmberSign, then open the helper to export. Requires the matching device App Store account/license and Developer Mode. Physical-device signing and decryption remain unverified. See [STOCK_DECRYPTION.md](STOCK_DECRYPTION.md).

## Jailbreak decryption export (0.5.0)

The separate rootless DEB adds installed-app decryption and IPA export. The ordinary sideloaded IPA keeps downloading encrypted App Store packages. Device decryption compatibility is unverified. See [DECRYPTION.md](DECRYPTION.md) for installation, implementation and limits.

# AppVault

Native iOS app for account-authorized IPA downloads from Apple.

## Trusted-device approval (0.4.3)

The Account screen now handles Apple-issued verification sessions and can request a prompt on trusted devices, submit its code against the same session and resume Store sign-in. This is the AppVault Store login flow, not Apple's Settings sign-in sheet. A bare HTTP 406 is not assumed to be a verification challenge. Approval requests are available only when Apple provides valid session context. The client now accepts JSON/plist responses and requests session creation. Physical-device prompt delivery and actual account login remain unverified.

## Current authentication

Version 0.4.2 replaces the unsigned 0.4.1 request with SAP signing, Store AMD device attestation (RP/SP provisioning) and kbsync IPA authorization. SAP alone was tested and did not reach business login; that candidate was not released. The replacement uses the local WebKit authentication runtime from mengangs/ipadn, pinned at `81dd1f747e71b31629979e2c1de0fe234fe7de39`. No jailbreak, user-enabled JIT, desktop helper or credential relay is required.

The first sign-in downloads approximately 58 MB of pinned runtime components from the upstream GitHub repository. Every SHA-256 must match the committed manifest before execution. Runtime components run locally, with a nonpersistent WebKit store, restricted local-origin navigation/CSP and a loopback server bound to 127.0.0.1 with a random URL capability. Its setup proxy allows only three exact Apple HTTPS endpoints. The app itself sends login credentials to Apple; no external service receives them. Apple certificate verification remains enabled. The IPA does not redistribute extracted Apple runtime libraries.

## Accounts and packages

Enter credentials in AppVault's Account screen and submit a trusted-device verification code when Apple requests it. Passwords/codes remain in memory during that challenge and are cleared after completion/cancellation. Password tokens, cookies and Store provisioning records are kept in device-only Keychain storage. Public search needs no sign-in. Downloads request the account-authorized IPA with locally generated kbsync and Store proof, then add supplied SINF and iTunes metadata. Apple DRM remains; sideloadability is not guaranteed.

## Verification

The live probe received an HTTP 200 SP challenge, completed local Store provisioning and obtained an HTTP 200 business authentication response with proof attached. Invented credentials were used; that verifies proof acceptance, not real-account login or verification-code delivery. CI also verifies pinned runtime hashes, executes the runtime smoke tests, checks protocol fixtures and compiles the iOS app. Physical-device login, actual IPA downloads and native exports remain unverified.

## Source and notices

Runtime adapter, loopback server and Apple plist normalization were adapted from the pinned GPL-2.0-or-later iPadn source. Notices and runtime provenance are included. Components are fetched on-device rather than bundled into AppVault's release. The upstream runtime provenance notes that a complete license grant for all binary components is not established; do not describe these binaries as AppVault-authored code or relicense them.

Build with Xcode 26.2+, XcodeGen and ldid using `.github/workflows/ios-build.yml`. AppVault shows installed version/build from package metadata. Diagnostics provide verified Copy, native Share, Files text export and selectable text.
