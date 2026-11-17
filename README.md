# AppVault

Native iOS app for account-authorized IPA downloads directly from Apple.

Version 0.4.1 replaces the experimental ipatool/Unicorn backend from 0.4.0 with a native URLSession client following the Store protocol observed in DLiPA. No JIT, jailbreak, desktop companion, credential relay, Apple framework asset download or additional root certificate is required by the implementation.

## Authentication limitation

DLiPA itself has current login failures. Reproducing its direct request format does not establish that Apple will accept it. Apple can reject unsigned Store authentication requests with HTTP 403; AppVault reports that explicitly. Physical-device sign-in, 2FA and real downloads remain unverified. A successful compile is not a verified login fix.

## Features

Search the public App Store, sign in using an Apple Account and a verification code when required, and request owned apps through volumeStoreDownloadProduct. An optional external version ID requests a specific build when Apple serves it. Obtain licenses through the App Store first; AppVault does not buy apps automatically. Saved files are validated IPA packages with supplied Apple SINF and metadata added, not app-data ZIP backups. Apple DRM remains and sideloadability is not guaranteed.

Session tokens and cookies are stored only in this app's device-only Keychain. Passwords and verification codes remain in memory for the login challenge and are cleared after completion/cancellation. Store redirects are limited and restricted to Apple HTTPS hosts; credential headers/cookies are not attached to the separate CDN session. No certificate trust bypass is implemented.

## Build and tests

Use macOS, Xcode, XcodeGen and ldid. Run `python3 scripts/check_version_ui.py`, then the Swift protocol fixtures shown in `.github/workflows/ios-build.yml`. Generate the Xcode project with `xcodegen generate` and build the AppVault scheme for iphoneos. The workflow builds and publishes the IPA and updates `repo.json` only after successful checks.

## Protocol evidence

The request layout was checked against the official DLiPA 1.4 binary: Configurator/2.20 User-Agent, XML property-list login body, form-urlencoded content type, appleId/attempt/createSession/guid/password/rmp/why keys, live bag lookup and volumeStoreDownloadProduct request. No DLiPA executable or closed-source implementation is bundled. The direct client is first-party AppVault code. MIT-licensed majd/ipatool's published SINF layout was used as protocol reference; existing third-party source notices remain intact.

Diagnostics provide verified Copy, native Share, Files text export and selectable text. Device verification of those paths remains pending.
