# Changelog

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
