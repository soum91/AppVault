# AppVault

Native iOS app for account-authorized IPA downloads directly from Apple.

## Account login

Version 0.4.2 replaces the unsigned request from 0.4.1 with the complete native `ApplePackage.Authenticator`, pinned to `391bfe6ee6598d73e4f94b88b38b50bd6f6ec67b`. It establishes fresh SAP state, signs the exact outgoing body in `X-Apple-ActionSignature`, and retains the same authentication actor for verification-code continuation. Swift/C arithmetic and OpenSSL implement signing locally. No JIT, jailbreak, emulator, private Apple executable or credential relay is used.

The earlier claim that a direct unsigned DLiPA-style request was sufficient was incomplete. Apple's authentication service rejects unsigned requests with HTTP 403. This version fixes the missing signing step using the maintained implementation also used by Asspp.

Enter your real Apple Account credentials only in AppVault's Account screen. Session tokens and cookies are stored in device-only Keychain. Raw passwords and codes are not persisted. We map the upstream account into a token-only model and never call the library's file-based account storage APIs. No extra root CA or certificate trust override is required.

## Verification

CI runs the pinned library's signing, handshake and authentication request unit tests and a controlled live probe. The live release gate requires signed authentication to reach an HTTP 200 plist business response while otherwise equivalent unsigned and corrupted signatures receive HTTP 403. The probe uses invented credentials and does not establish actual user login, code delivery or downloads. Physical-device account login and IPA/export testing remain unverified.

## IPA packages

Search the public App Store, sign in, and request owned packages through `volumeStoreDownloadProduct`. Account tokens, cookies, DSID, storefront and pod from successful authentication are used for downloads. An optional external version ID requests a specific build when Apple serves it. Obtain licenses through the App Store first. Files are validated IPA packages with supplied Apple SINF and iTunes metadata added, not app-data backups. Apple DRM remains; sideloadability is not guaranteed.

## Build

Use Xcode 26.2 / Swift 6.2+, XcodeGen and ldid. Run the checks in `.github/workflows/ios-build.yml`, generate the Xcode project, and build the AppVault scheme for iphoneos. The workflow publishes a prerelease and refreshes `repo.json` only after all required checks pass.

ApplePackage is MIT-licensed; its notice is bundled. Existing third-party notices remain intact. Diagnostics offer verified Copy, Share, native Files text export and selectable text. Physical-device verification of these export paths remains pending.
