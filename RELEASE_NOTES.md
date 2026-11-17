# AppVault 0.6.0 (13)

Adds **IPAs > Decrypt on Stock iOS**. Choose a saved/imported licensed IPA to prepare a separate per-app helper. Sign/install that helper with payload-preserving EmberSign, open it, and attempt local decryption/export. The helper keeps the target as installed resources, checks every embedded file hash, then shares a completed IPA only after all supported encrypted Mach-O slices pass page-read and encryption-marker checks. Includes nested frameworks and app extensions; watchOS content is omitted.

Signing compatibility: requires the EmberSign AppVault-helper preservation update. Older EmberSign and FlareStore are not claimed compatible. The helper has its own identifier and ordinary entitlements. Requires matching device App Store account/license, development signing, Developer Mode, and a new helper installation for each target. Prepared helpers are not decrypted output.

Refactors jailbreak and helper exports onto one implementation and shares the diagnostic component. Adds host preparation fixtures for resource integrity, license replication, tampering, missing licenses and path traversal. Keeps the rootless DEB export and App Store download/login flows.

The public FairPlayed research reports stock iOS 27.0.1 support; AppVault's adaptation is original code, with no FairPlayed source vendored. Physical-device helper signing, actual decryption, and diagnostic Copy/Share/Save remain unverified. Build/fixture success does not establish successful device decryption. See STOCK_DECRYPTION.md for instructions and limits.
