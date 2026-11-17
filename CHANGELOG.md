# Changelog

## [v0.4.4] - 2026-11-17

## Verified changes since v0.4.3

- Package account-bound verification changes as AppVault 0.4.4 build 11 ([`88cb835d`](https://github.com/soum91/AppVault/commit/88cb835db8b8a443cf3568888b8e9bd334af1166); `.github/workflows/ios-build.yml`, `BUILD_VALIDATION.md`, `RELEASE_NOTES.md`, and 1 more)
- Bind pending device verification to its account and describe the local runtime accurately ([`b3342f61`](https://github.com/soum91/AppVault/commit/b3342f614a1e6d9b3bf331536c9afff84b04e73b); `AppVault/DirectAppleStore.swift`, `AppVault/StoreService.swift`)

[Inspect exact code changes](https://github.com/soum91/AppVault/compare/v0.4.3...v0.4.4)

## [v0.4.3] - 2026-11-17

## Verified changes since v0.4.2

- Handle Apple verification sessions before HTTP errors and request trusted-device approval ([`acc5667c`](https://github.com/soum91/AppVault/commit/acc5667ccf9e57192bd653bcb6875c8b1c0ee39a); `.github/workflows/ios-build.yml`, `AppVault/AppleVerification.swift`, `AppVault/BackupHomeView.swift`, and 9 more)

[Inspect exact code changes](https://github.com/soum91/AppVault/compare/v0.4.2...v0.4.3)

# 0.4.4 (11) - account-bound verification

AppVault 0.4.4 (11): account-bound verification sessions

- Clears a pending trusted-device verification context when signing in with a different account, preventing reuse of the preceding account's approval session.
- Corrects diagnostics to identify the local WebKit/WASM authentication runtime and distinguish it from user-enabled JIT, which is not required.
- Retains 0.4.3's broader Accept header, structured challenge parsing before HTTP-error rejection, session creation, trusted-device approval requests, code verification and redacted response traces. A bare HTTP 406 is not treated as evidence of two-factor authentication.

Validation: the verification-session fixtures, runtime integrity/smoke checks, live Store-proof acceptance and iOS compilation remain mandatory. 0.4.3 passed those checks before this follow-up. Real-account notification delivery, code verification, login, IPA download and exports remain unverified on a physical device. A notification request accepted by Apple does not prove that a trusted device displayed it.


# 0.4.3 (10) - trusted-device verification

AppVault 0.4.3 (10): trusted-device verification and HTTP 406 handling

- Replaces the XML-only Accept header with */* on Store requests so login can negotiate Apple's JSON, plist and challenge responses. The prior client's header was overly restrictive; this is a compatibility fix, not proof that it caused every 406.
- Requests createSession in the signed login payload. Decodes structured response fields before classifying HTTP failures, preserving verification and Store-device challenges carried with non-2xx replies.
- Recognizes Apple-issued X-Apple-ID-Session-Id/scnt context and explicit two-factor challenges. A bare HTTP 406 or an explicit credential rejection is not treated as proof that device approval is available.
- With a valid verification session, requests trusted-device approval through Apple's idmsa endpoint, reveals the code field, and provides Request Approval and Cancel Verification actions. Code verification uses the same session, tracks rotated session headers/cookies, then resumes signed Store login. Legacy code-only continuation remains available when Apple does not provide a session for sending notifications.
- Keeps verification session identifiers ephemeral and excludes passwords, codes, session IDs and scnt from reports and account serialization. Approval success is shown only when Apple accepts the request; it does not claim that a device displayed a prompt.
- Adds redacted response diagnostics with stage, HTTP status, payload size/format and challenge/session presence so a failure can be located without exposing account data.

Validation: protocol fixtures cover HTTP 406 JSON challenge parsing, rejection without session headers, explicit bad credentials, trusted-device request methods/body/headers and rotated scnt. Existing Store-proof/runtime gates and iOS compilation remain mandatory. The live Store probe uses invented credentials and cannot exercise trusted-device delivery. Real-account approval, 2FA, login, IPA download and exports remain unverified on a physical device.


# Changelog

## [v0.4.2] - 2026-11-17

## Verified changes since v0.4.1

- Retain Store routing across verification and test initial versus code-submission attempts ([`ce0fc0ea`](https://github.com/soum91/AppVault/commit/ce0fc0eafeb728d2a579ad9f988fce1c2690581d); `AppVault/DirectAppleStore.swift`, `AppVault/StoreProtocol.swift`, `Tests/StoreProtocol/main.swift`)
- Add local Store AMD provisioning and kbsync using pinned no-user-JIT WebKit runtime ([`8b93c2aa`](https://github.com/soum91/AppVault/commit/8b93c2aae4d11d5b5dc478fd3d3fd604e333711c); `.github/workflows/ios-build.yml`, `AppVault/Attestation/ApplePropertyList.swift`, `AppVault/Attestation/LocalSAPSigner.swift`, and 15 more)
- Replace unsigned login with native SAP-signed ApplePackage Authenticator and retained 2FA session ([`ceb1ea49`](https://github.com/soum91/AppVault/commit/ceb1ea498003b51607375468f6d48ea1f199d018); `.github/workflows/ios-build.yml`, `AppVault/ApplePackage-LICENSE.txt`, `AppVault/BackupHomeView.swift`, and 7 more)

[Inspect exact code changes](https://github.com/soum91/AppVault/compare/v0.4.1...v0.4.2)

## [v0.4.1] - 2026-11-17

## Verified changes since v0.3.1

- Replace emulator with DLiPA-style native direct Apple Store login and IPA downloads ([`dd61ecfb`](https://github.com/soum91/AppVault/commit/dd61ecfbd84699258d0c109a4570edecd9ebb807); `.github/workflows/ios-build.yml`, `AppVault/BackupHomeView.swift`, `AppVault/DirectAppleStore.swift`, and 16 more)
- Persist cookies in secure session state and redact actionable backend errors ([`ce59f077`](https://github.com/soum91/AppVault/commit/ce59f077ce6ad3e18ffe91261b60fc4159e8dbb0); `AppVault/BackupHomeView.swift`, `AppVault/IPAToolService.swift`, `NativeIPATool/cookies.go`, and 3 more)
- Integrate pinned ipatool backend with native IPA UI and explicit JIT capability gate ([`d15b12c8`](https://github.com/soum91/AppVault/commit/d15b12c8ae2ed90a615f67e456dfdf1985749386); `.github/workflows/ios-build.yml`, `AppVault/BackupHomeView.swift`, `AppVault/IPAToolBridge.h`, and 10 more)
- Remove third-party DLiPA catalog substitution ([`8ffaec28`](https://github.com/soum91/AppVault/commit/8ffaec28eb1d6e9a69cfde6788597827f4f16d6f); `.github/workflows/catalog-dlipa.yml`, `repo.json`, `scripts/catalog_dlipa.py`)
- Preserve separately cataloged IPA tools when refreshing the AppVault listing ([`2b08375c`](https://github.com/soum91/AppVault/commit/2b08375c887ab27bddc2c0e5ed08de8e7cc7e1b7); `.github/workflows/ios-build.yml`)
- Catalog official DLiPA IPA downloader with metadata verification ([`e5d601f9`](https://github.com/soum91/AppVault/commit/e5d601f9ce77ee7c5362dd62cd5fe6508213e55c); `.github/workflows/catalog-dlipa.yml`, `scripts/catalog_dlipa.py`)

[Inspect exact code changes](https://github.com/soum91/AppVault/compare/v0.3.1...v0.4.1)

## [v0.1.0] - 2026-11-12

## Verified changes since project start

- Add AppVault/WorseQueryBridge.h ([`7abcf239`](https://github.com/soum91/AppVault/commit/7abcf2395c91bb4686a5672a1a965ac2ef1571ce); `AppVault/WorseQueryBridge.h`)
- Add AppVault/BackupService.swift ([`159da0db`](https://github.com/soum91/AppVault/commit/159da0dbcffc2c44be1a63634c9b8626fbb777c8); `AppVault/BackupService.swift`)
- Add AppVault/BackupHomeView.swift ([`18747bcf`](https://github.com/soum91/AppVault/commit/18747bcf21a51bc531bebf13ce85c4eb93f4aaa0); `AppVault/BackupHomeView.swift`)
- Add AppVault/BackupModels.swift ([`39a55264`](https://github.com/soum91/AppVault/commit/39a55264984faf9a9f15ed5a88c015b319cf2afb); `AppVault/BackupModels.swift`)
- Add AppVault/AppVaultApp.swift ([`34c41977`](https://github.com/soum91/AppVault/commit/34c419777f82a5679b82c6779fb0b7e90e95dfbe); `AppVault/AppVaultApp.swift`)

[Inspect exact code changes](https://github.com/soum91/AppVault/commits/v0.1.0)

# 0.4.2 (9) - Store-attested account login

AppVault 0.4.2 (9): Store-attested Apple login and IPA authorization

- Replaces 0.4.1's unsigned login with SAP request signing plus the current Store AMD device-proof flow. The first SAP-only candidate returned empty HTTP 204 in live testing and was blocked from release.
- Uses the pinned iPadn authentication runtime (81dd1f747e71b31629979e2c1de0fe234fe7de39) locally through a nonpersistent WebKit context. This requires no jailbreak or user-enabled JIT. It replaces the earlier unsuccessful Go/JIT and SAP-only approaches.
- Handles Apple's RP/SP actions, provisions the Store proof, refreshes proof headers for requests/redirects, and retains provisioning state in device-only Keychain. Existing session cookies and password-token storage remain on-device; passwords and verification codes are not saved.
- Uses Configurator/2.21, requests the current bag, preserves its advertised native authentication path, and signs the exact XML login body. Verification codes are submitted through the same AppVault account flow.
- Uses ent/download with locally generated kbsync and Store proof for IPA authorization, then validates and finishes the IPA with supplied license and metadata entries.
- Downloads the seven pinned runtime components once on the device and verifies every SHA-256 before execution. Extracted Apple runtime libraries are not included in AppVault's IPA. The local server binds only 127.0.0.1 behind a random path capability; its setup proxy permits only three fixed Apple URLs. WebKit navigation and network destinations are restricted to that local origin; Apple HTTPS certificate verification remains enabled.
- Preserves AppVault's bundle identifier, icon, Keychain service, account UI, file sharing and redacted Copy/Share/Files diagnostics. Includes upstream license and runtime provenance notices.

Validation: the live runtime probe received HTTP 200 with Apple's SP provisioning challenge, generated the Store proof locally, then received HTTP 200 business authentication with the proof attached. It used invented account credentials and does not establish real-account login or code delivery. The pinned runtime's offline smoke tests, direct protocol fixtures and iOS compilation are release gates. Physical-device login/2FA, real-account IPA downloads and exports remain unverified. Apple DRM remains.


# 0.4.1 (8) - direct native Store client

AppVault 0.4.1 (8): native direct Apple Store client

- Removes the Go archive, Unicorn emulator, JIT capability gate and Apple framework asset downloads introduced in 0.4.0.
- Implements Apple login with native URLSession HTTPS using the DLiPA-observed Configurator request format, live bag endpoint discovery, token-only Keychain account storage and persisted session cookies.
- Handles redirects through case-insensitive header lookup, relative URL resolution, a five-hop limit and validated Apple HTTPS destinations. Does not reproduce DLiPA's exact-case Location lookup.
- Keeps search, account sign-in, verification-code submission, IPA download, optional external version ID and native IPA sharing in AppVault. Public search works before login.
- Validates the downloaded bundle, adds supplied Apple SINF license data and iTunes metadata to the IPA, and only lists the file as saved after packaging completes. Downloaded packages remain protected by Apple's DRM.
- Preserves redacted diagnostics with verified Copy, Share and plain-text Files export. Passwords and verification codes are never written to account storage.

Validation: protocol fixtures cover redirect host boundaries, XML escaping and payload keys, header casing, token-only account encoding, explicit HTTP 403 rejection, 2FA challenge handling, SINF path traversal and CDN host validation. CI also checks installed-version metadata and compiles the device app. Physical-device Apple sign-in, actual IPA downloads, clipboard and Files export remain unverified.

Important limitation: no JIT or jailbreak is required by this native implementation. However, Apple's service can reject unsigned Store login with HTTP 403. This build reports that rejection and does not claim to bypass it or guarantee a working account login. An Apple Account app-specific password is not a substitute for this Store login protocol.


# 0.4.0 (7) - experimental integration

AppVault 0.4.0 (7), experimental build artifact

- Replaces the primary app-data browser with native Apple Account, App Store search, IPA download and saved-file sharing screens.
- Links majd/ipatool at b352566155a667d8aaeabaa7ecec4966080f92ab into the app process through a Go C archive. Uses upstream's pinned Unicorn 2.1.4 source, integrity check and iOS W^X patch.
- Checks executable-memory capability before sign-in. This backend requires JIT or a compatible jailbreak; worse_query alone is insufficient. No JIT enablement mechanism is included.
- Stores tokens and provisioning state in device-only Keychain storage. Strips the login password before persisting upstream account records. Uses a private random persistent device identity rather than reading a hardware address.
- Reports download byte progress and supports cancellation during runtime preparation and file transfer. Apple authentication requests may finish before cancellation takes effect.
- Apple DRM remains. This downloads Apple-authorized packages, not installed-app binary extraction.

Validation: password-stripping and credential-clearing fixtures run in CI before packaging; installed-version preflight and iOS compilation are required. Physical-device authentication, JIT compatibility, clipboard/export and IPA reinstallation are unverified. Artifact-only; do not update the FlareStore feed or publish as a working replacement until device testing succeeds.


# Changelog

## Catalog restoration

- Restore the official DLiPA listing at the owner's request, retaining AhmedBafkir attribution and the upstream IPA download URL. No AppVault application feature is added.


## Catalog correction

- Remove the DLiPA third-party listing and its catalog workflow/script. Adding an external application did not implement the requested IPA backup feature in AppVault.
- Clarify the current AppVault source description; no new app functionality is claimed.


## Catalog update

- Add a separately attributed DLiPA entry pointing to the official AhmedBafkir release asset, with bundle/version/build read from the actual IPA.
- Clarify that DLiPA downloads App Store packages through an Apple Account; it does not extract the installed binary. No AppVault application feature is claimed by this catalog addition.


## 0.3.1 (6)

- Fix the app-data backup failure on Apple's protected .com.apple.mobile_container_manager.metadata.plist by copying Documents and Library rather than the whole container.
- Exclude Library/Caches, tmp and container-management files; record exclusions and copied file/byte counts in backup-manifest.json.
- Continue to abort on unreadable user data or symbolic links; remove incomplete ZIP output on archive failure.
- Add host regression fixtures covering protected metadata, preserved data, exclusions, unreadable user files and symbolic links.

Evidence: AppVault/AppDataCopy.swift, BackupService.swift and Tests/main.swift in this release.
Validation: host fixtures and device compilation run in GitHub Actions before publication. The reported physical-device metadata failure has not been retested on the user's device. This remains app-data ZIP backup; installed IPA extraction on iOS 27.0.1 remains unsupported.


## [v0.3.0] - 2026-11-15

## Verified changes since v0.2.1

- Use typed name adapters for the vendored database parser ([`09d5f003`](https://github.com/soum91/AppVault/commit/09d5f0034b5f7cc07acae512b15935255b0386ee); `AppVault/Discovery/WQLocalization.h`)
- Define discovery bridge nullability and preserve interrupted scan chunks ([`d7f61150`](https://github.com/soum91/AppVault/commit/d7f611501c293fa355c2ae43535da178f1d7f8ab); `AppVault/Discovery/AVDiscovery.m`, `AppVault/WorseQueryBridge.h`)
- Replace unbounded discovery with LaunchServices database search and expose actual failures ([`b9af5040`](https://github.com/soum91/AppVault/commit/b9af50406bd1ab151b9853d3fa869416c6ae8e4f); `.github/workflows/ios-build.yml`, `AppVault/BackupHomeView.swift`, `AppVault/BackupService.swift`, and 9 more)
- ci: block AppVault IPA publication on version UI contract ([`0e489c8e`](https://github.com/soum91/AppVault/commit/0e489c8ebc0f8de219f19fbc54d1c4357b0bda33); `.github/workflows/ios-build.yml`)
- ci: enforce AppVault installed version and build contract ([`466cffd2`](https://github.com/soum91/AppVault/commit/466cffd2cd9a7187c58e45ea08122b0d767f50c0); `.github/workflows/version-ui.yml`)
- ci: enforce AppVault installed version and build contract ([`4379f2f9`](https://github.com/soum91/AppVault/commit/4379f2f9d47dad6914b01b0260a2b57af10174fe); `scripts/check_version_ui.py`)
- ci: enforce AppVault installed version and build contract ([`ddaeea0f`](https://github.com/soum91/AppVault/commit/ddaeea0fe5ebd96a4bc1e158dc7551d18c4d78a6); `version-ui-contract.json`)
- fix: display installed AppVault version and build from Info.plist ([`9c160acd`](https://github.com/soum91/AppVault/commit/9c160acd9b2d75ed1b70472f3d343eeeadda62d3); `AppVault/BackupHomeView.swift`)

[Inspect exact code changes](https://github.com/soum91/AppVault/compare/v0.2.1...v0.3.0)

## 0.3.0 (5)

- Replace automatic ascending full-volume container scans with a 20-second descending search for the LaunchServices database. Resume unsuccessful searches from a saved cursor.
- Read app names and data paths using the GPL-3.0 WQFiles database parser; reuse the remembered database location.
- Check for a usable signed App Group and validate fsgetpath against an app-owned probe before searching.
- Show checked-ID counts and elapsed time, and support cancellation.
- Add selectable discovery diagnostics with verified clipboard copy, native share and Files export.
- Remove the App Bundle shortcut and explicitly document that installed IPA extraction on iOS 27.0.1 is unsupported by this access method.

Evidence: changes to AppVault/Discovery, BackupService.swift and BackupHomeView.swift in this release commit.
Limitations: compilation and archive metadata can be verified by CI. App-container discovery, backup, clipboard, Share and Files export have not been tested on a signed physical device by the maintainer in this session. No claim of working installed-IPA extraction is made.

## [v0.2.1] - 2026-11-12

## Verified changes since v0.2.0

- Fix container discovery fallback and bundle AppVault icon in 0.2.1 ([`dfb8d597`](https://github.com/soum91/AppVault/commit/dfb8d597ad4a940c0c3c014a2d743394006b1d1c); `.github/workflows/ios-build.yml`, `AppVault/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, `AppVault/Assets.xcassets/AppIcon.appiconset/Contents.json`, and 6 more)

[Inspect exact code changes](https://github.com/soum91/AppVault/compare/v0.2.0...v0.2.1)

## [v0.2.0] - 2026-11-12

## Verified changes since v0.1.1

- Build and publish AppVault 0.2.0 with entitlements and refresh FlareStore feed ([`483bc416`](https://github.com/soum91/AppVault/commit/483bc4166334acad5a7a8807423ce35d09e99e30); `.github/workflows/ios-build.yml`)
- Integrate worse_query access, app browser and real folder backup in 0.2.0 ([`49cc11b1`](https://github.com/soum91/AppVault/commit/49cc11b14a4bb677f0252e75d364101b2068b8bd); `AppVault/Access.m`, `AppVault/AppVault.entitlements`, `AppVault/BackupHomeView.swift`, and 9 more)
- Document FlareStore source URL ([`ef6c11e2`](https://github.com/soum91/AppVault/commit/ef6c11e2f03752e835490cc5f154b5e1976969e5); `README.md`)
- Add AltStore-compatible FlareStore source ([`fc7a7ff3`](https://github.com/soum91/AppVault/commit/fc7a7ff3d79d9042214019a3d6021db39917aa07); `repo.json`)

[Inspect exact code changes](https://github.com/soum91/AppVault/compare/v0.1.1...v0.2.0)

## [v0.1.1] - 2026-11-12

## Verified changes since v0.1.0

- Set AppVault app version to 0.1.1 (2) ([`8e126f6a`](https://github.com/soum91/AppVault/commit/8e126f6a3cb3d970a27307581e343d6b07d78e1f); `project.yml`)

[Inspect exact code changes](https://github.com/soum91/AppVault/compare/v0.1.0...v0.1.1)

## 0.2.1 (4)
- Discover individual application containers instead of requesting an unsupported parent-directory extension.
- Fall back to path discovery when installed-application enumeration returns no results.
- Normalize /private/var discovery paths and add scan cancellation.
- Include an archive-box app icon in the iOS bundle and FlareStore source.

## 0.2.0 (3)
- Integrated worse_query, pathleak, folder browsing and backup export.
