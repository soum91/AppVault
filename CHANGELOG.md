# Changelog

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
