# Changelog

## [v0.6.6] - 2026-11-18

- Rootless Decryptor regains Apple Account sign-in: the pinned SAP runtime
  runs in-process with JavaScriptCore (`InProcessSAPRuntime.swift`), so no
  WebContent process is spawned.
- Add `dynamic-codesigning` to the jailbreak entitlements for JavaScriptCore
  JIT/WebAssembly; explicit error if it is still unavailable.
- Build the Decryptor from the shared sources with `APPVAULT_ROOTLESS`, which
  compiles WebKit out; CI rejects a WebKit-linked rootless binary.
- Native shims for URL, fetch (loopback only), timers, TextEncoder/Decoder,
  crypto and script loading, tested in CI in a bare JavaScript realm.
- IPA build stops cold WebKit attempts once WebContent exits during attach.
- Release assets carry build 19. Rootless device sign-in remains unverified.

## [v0.6.5] - 2026-11-18

- Replace the all-in-one rootless AppVault application with a standalone
  privileged **AppVault Decryptor**. Keep account-based Store downloads in
  the separate ordinary sandboxed AppVault IPA.
- The Dopamine iOS 16.1.1 device repeatedly terminated the privileged app's
  WebKit content process before page navigation; the new rootless app does not
  include the WebKit authentication runtime.
- Preserve the installed rootless Debian package ID for in-place Sileo upgrades,
  migrate the icon path, and keep the existing rootless export storage.
- Expose actual installed version/build in the Decryptor UI and add CI
  checks preventing Store/WebKit code from entering the privileged target.
- Functional installed-app export, stock AppVault account login and FairPlay
  handling remain unverified on a physical device.


## [v0.6.4] - 2026-11-18

- Keep the SAP/WASM WebKit view visibly attached at 140pt height instead of
  an almost invisible 1×1 view while signing on iOS 16.
- Do not shut down the active local signing proxy when iOS posts a memory
  warning; reset only an idle runtime.
- Show `WEB_CONTENT_EXIT` when WebKit's content process terminates and record
  safe local signer stages in the Backend Report for device diagnosis.
- Add CI guards for these regressions; actual login on iOS 16.1.1 remains
  unverified until a device test.


## [v0.6.3] - 2026-11-18

- Expose existing Apple Account verification-code entry for both sandboxed and
  rootless builds without waiting for a challenge to show the field.
- Keep server-issued trusted-device approval and HSA2 session verification gated
  by valid Apple response context, rather than inventing a push request.
- Validate six-digit codes and clear manually entered codes on dismissal.
- Add regression checks for the manual code UI and retained signed Store flow.
- SAP/WebKit signer failures before 2FA remain unresolved until reproduced with
  a current-version on-device Backend Report.


## [v0.6.2] - 2026-11-18

- Display locally produced `ToolError` descriptions instead of dropping them and showing `AppVaultToolError code 0`.
- Preserve numeric local WebKit signer failures without leaking JavaScript exceptions, URLs or account secrets.
- Clarify empty local-signing results and missing loopback address in English.
- Actual iOS 16 Apple Account login remains unverified on device.


## [v0.6.1] - 2026-11-18

- Surface Apple sign-in stages and seven runtime asset download/verification steps in the progress banner.
- Bound pinned authentication component network waits and preserve checksum validation.
- Include the stage of a failed sign-in in the Backend Report to diagnose device-specific stalls.
- No claim of verified Dopamine login, IPA download or FairPlay decryption.


## [v0.6.0] - 2026-11-18

## Verified changes since v0.5.0

- Use canonical relative paths for IPA integrity and decryption ([`4d7f83ea`](https://github.com/soum91/AppVault/commit/4d7f83ea1573eda654da3ea43d7d2fa19040ae88); `AppVault/Decryption/IPAExportEngine.swift`)
- Use canonical relative paths for IPA integrity and decryption ([`fec58499`](https://github.com/soum91/AppVault/commit/fec58499274e84179f5f5b28a663553482d0c5a1); `AppVault/Decryption/HelperManifest.swift`)
- Use canonical relative paths for IPA integrity and decryption ([`e05e5f26`](https://github.com/soum91/AppVault/commit/e05e5f269baa01e249dc0531a30172c56a6db1ed); `AppVault/Decryption/HelperPreparation.swift`)
- Canonicalize /tmp and /private/tmp before verifying helper payload paths ([`c0fe604a`](https://github.com/soum91/AppVault/commit/c0fe604a38d793b12bc2777c209fa956e6c48d37); `AppVault/Decryption/HelperManifest.swift`)
- Avoid unavailable URLSession temp download container during rootless authentication ([`2ff17b19`](https://github.com/soum91/AppVault/commit/2ff17b196e70aae5d672c4242524e891128017f5); `AppVault/Attestation/RuntimeAssets.swift`)
- Show AppVault installation mode and storage location in diagnostic report ([`023de8d5`](https://github.com/soum91/AppVault/commit/023de8d552c9b08c24f13904d8826c51aca1760e); `AppVault/StoreService.swift`)
- Detect rootless AppVault installation path even when privilege signing is unavailable ([`1469e85a`](https://github.com/soum91/AppVault/commit/1469e85a972fe46df50e5ec12030dd23c08ea0af); `AppVault/VaultStorage.swift`)
- Document AppVault permission error 513 fix and physical-device validation boundary ([`cd1b1a40`](https://github.com/soum91/AppVault/commit/cd1b1a4000e671dde6820e2ac59f56024b4f3e8d); `RELEASE_NOTES.md`)
- Use writable rootless temporary storage and preserve SINF resources for stock helper ([`2e304606`](https://github.com/soum91/AppVault/commit/2e304606ea5e50b569b49a905f99fb9ae0244ae9); `AppVault/Decryption/StockPreparationView.swift`)
- Use writable rootless temporary storage and preserve SINF resources for stock helper ([`87bc5376`](https://github.com/soum91/AppVault/commit/87bc537611d88abc4a697389d542ea7a6eb0abe6); `AppVault/Decryption/HelperPreparation.swift`)
- Use writable rootless workspace for installed-app decryption exports ([`0ab49646`](https://github.com/soum91/AppVault/commit/0ab49646f2259aa124d769c0d9fd91cb5136e5f0); `AppVault/Decryption/DecryptionService.swift`)
- Use writable rootless workspace for installed-app decryption exports ([`6833d9dc`](https://github.com/soum91/AppVault/commit/6833d9dc94d81f7a9db54743fea08182131b7d48); `AppVault/Decryption/IPAExportEngine.swift`)
- Provision mobile-owned AppVault storage during rootless DEB installation ([`05aff408`](https://github.com/soum91/AppVault/commit/05aff408ea2d4e5eb37b6f855dada3d5384d27d7); `packaging/rootless/DEBIAN/postinst`)
- Preflight AppVault auth writes and report local permission failures accurately ([`49256235`](https://github.com/soum91/AppVault/commit/4925623571c573efcf63d60456f705eabec085d7); `AppVault/StoreService.swift`)
- Use mobile-owned runtime directory for rootless authentication assets ([`1cf36b1c`](https://github.com/soum91/AppVault/commit/1cf36b1c331c4182fc3845de67d0c929c65c5780); `AppVault/Attestation/RuntimeAssets.swift`)
- Add dedicated writable rootless AppVault storage with permission diagnostics ([`ffd7fa23`](https://github.com/soum91/AppVault/commit/ffd7fa23553157f07366d0c14b5fd17d3d719683); `AppVault/VaultStorage.swift`)
- Specify archive fixture size at ZIPFoundation overload boundary ([`3e885cc2`](https://github.com/soum91/AppVault/commit/3e885cc2d74a1d8a829c917d4c83c4d133c5cb0b); `Tests/HelperPreparation/Tests/HelperPreparationTests/PreparationTests.swift`)
- Prepare licensed stock iOS helper IPAs and export decrypted embedded apps ([`86730de0`](https://github.com/soum91/AppVault/commit/86730de0cd69cc026b6ce1ef0ff006d978b5f3ae); `.github/workflows/ios-build.yml`, `AppVault/BackupHomeView.swift`, `AppVault/Decryption/DecryptionService.swift`, and 17 more)

[Inspect exact code changes](https://github.com/soum91/AppVault/compare/v0.5.0...v0.6.0)

# AppVault 0.6.0 (13)

Adds **IPAs > Decrypt on Stock iOS**. Choose a saved/imported licensed IPA to prepare a separate per-app helper. Sign/install that helper with payload-preserving EmberSign, open it, and attempt local decryption/export. The helper keeps the target as installed resources, checks every embedded file hash, then shares a completed IPA only after all supported encrypted Mach-O slices pass page-read and encryption-marker checks. Includes nested frameworks and app extensions; watchOS content is omitted.

Signing compatibility: requires the EmberSign AppVault-helper preservation update. Older EmberSign and FlareStore are not claimed compatible. The helper has its own identifier and ordinary entitlements. Requires matching device App Store account/license, development signing, Developer Mode, and a new helper installation for each target. Prepared helpers are not decrypted output.

Refactors jailbreak and helper exports onto one implementation and shares the diagnostic component. Adds host preparation fixtures for resource integrity, license replication, tampering, missing licenses and path traversal. Keeps the rootless DEB export and App Store download/login flows.

The public FairPlayed research reports stock iOS 27.0.1 support; AppVault's adaptation is original code, with no FairPlayed source vendored. Physical-device helper signing, actual decryption, and diagnostic Copy/Share/Save remain unverified. Build/fixture success does not establish successful device decryption. See STOCK_DECRYPTION.md for instructions and limits.

# Changelog

## [v0.5.0] - 2026-11-17

## Verified changes since v0.4.4

- Convert native slice counts at Swift decryption bridge boundary ([`7bb93626`](https://github.com/soum91/AppVault/commit/7bb936267daeab01083f4d809d8adb02e2be9b38); `AppVault/Decryption/DecryptionService.swift`)
- Reject unchecked bundle entries and make copied binaries writable for export ([`38990398`](https://github.com/soum91/AppVault/commit/3899039818e624a2f931a632c417be74fb0de344); `AppVault/Decryption/DecryptionService.swift`, `DECRYPTION.md`)
- Add privileged installed-app decryption and verified IPA export with rootless package ([`20471858`](https://github.com/soum91/AppVault/commit/20471858122ce88c9b6bace4b3eb105764c37ff7); `.github/workflows/ios-build.yml`, `AppVault/Access.m`, `AppVault/BackupHomeView.swift`, and 13 more)

[Inspect exact code changes](https://github.com/soum91/AppVault/compare/v0.4.4...v0.5.0)

## [v0.3.1] - 2026-11-17

## Verified changes since v0.3.0

- Fix app-data backup copying protected container metadata; add copy regression fixtures ([`bd6f8612`](https://github.com/soum91/AppVault/commit/bd6f8612f4e290acdae3679b7fce8b31e3d59281); `.github/workflows/ios-build.yml`, `AppVault/AppDataCopy.swift`, `AppVault/BackupService.swift`, and 3 more)

[Inspect exact code changes](https://github.com/soum91/AppVault/compare/v0.3.0...v0.3.1)

# AppVault 0.5.0 (12)

Adds **IPAs > Decrypt Installed Apps** and a separate rootless jailbreak DEB. Select an installed user app, copy its app bundle, decrypt supported encrypted arm64 Mach-O slices with the device's FairPlay service, verify all copied binaries, and package `Payload/<App>.app` as an IPA. Includes nested frameworks and extensions; any unsupported or failed binary aborts the export and reports its failure. Original installed apps and earlier exports remain untouched.

The normal IPA keeps its limited entitlements and saves encrypted Apple downloads. Use the jailbreak DEB on the jailbroken device containing the installed app and matching App Store license. This does not add arbitrary-file decryption on stock iOS. See DECRYPTION.md for implementation, limitations and research attribution.

Validation: C parser fixtures and installed-version preflight passed locally. CI runs parser/protocol/runtime checks and compiles/packages both assets. Actual decryption on a physical jailbroken device, entitlement acceptance and diagnostic Copy/Share/Save remain unverified. Exported apps still need suitable signing.

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


## [Unreleased] Rootless AppVault storage correction

- Rootless AppVault now uses a mobile-owned persistent data directory for its local Apple request signing runtime and IPA exports instead of depending on a sandbox data-container URL.
- Rootless post-install script provisions protected authentication, temporary, and export directories. Preflight detects unwritable storage before accepting Apple credentials.
- Report `NSCocoaErrorDomain 513` as a filesystem permission failure, not an Apple login/network failure.
- Share a writable temp workspace with the installed-app decryption and stock helper preparation flows without relaxing authorization or FairPlay checks.
- Preserve nested SINF license resources via independent writes. Actual on-device login and decryption remain unverified.
