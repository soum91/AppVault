# Stock iOS decryption helpers (0.6.0)

## On-device workflow

1. Update AppVault. Open **IPAs > Decrypt on Stock iOS** and select a saved account-authorized IPA, or import one from Files.
2. AppVault embeds its target app as resources in a separate compiled helper. It preserves encrypted binaries and license files, replicates license locations declared by Apple's manifest, removes watchOS content, and records every embedded file's SHA256.
3. Share the prepared helper IPA to the **payload-preserving EmberSign release** linked in the AppVault release notes. Sign using your development certificate/profile and install. Enable Developer Mode. The helper uses `com.soum91.appvault.decrypthelper`, not the target app's identifier.
4. Open **Decrypt <app>** and tap **Decrypt and Export IPA**. The helper verifies the embedded resources before attempting FairPlay page reads, then packages a separate output only if every encrypted slice passes. Share the decrypted IPA from the helper or Files > On My iPhone > Decrypt <app> > Decrypted.

A matching App Store license is required, and the device must be signed into the Apple Account that owns the target app. AppVault's own sign-in is not a substitute for the device's FairPlay account. The target's code is never executed by the helper. One helper installation handles one app; preparing another target reuses the helper identifier. Free signing slot and expiry limits still apply.

## Why reinstall a helper?

The system FairPlay service can read binaries/licenses from installed app bundles, but cannot read them from AppVault's writable Downloads directory. The target therefore has to become a resource of a newly signed and installed helper. This is not an instant decryption button for arbitrary files in Downloads.

The approach is based on the public FairPlayed research, which reports stock iOS 27.0.1 testing:
https://github.com/morzelowski/FairPlayed

AppVault's adaptation is original code sharing its existing read-only mapping/decryption engine. No FairPlayed source is vendored. Our integration, on-device signing and physical-device export are **unverified**. Build and host fixtures do not demonstrate actual FairPlay decryption.

## Signer compatibility

Use EmberSign with explicit AppVault-helper resource preservation. Ordinary Zsign-based signers may recursively rewrite the target's encrypted Mach-O files, nested Info.plist files or licenses. AppVault checks all embedded file hashes and rejects such changes. FlareStore and older EmberSign versions are not claimed compatible. Do not strip extensions, libraries or resources, inject tweaks, or change the embedded target's identifier when signing the helper.

## Output and errors

- A prepared **helper IPA is still encrypted**. The installed helper must complete the export before you have a decrypted target IPA.
- `FairPlay rejected mapping` or `FairPlay page read failed` is a real device/OS/license failure. No successful output is published for that attempt.
- All supported encrypted arm64 slices must change and read completely before their copied cryptid is cleared. Original resources remain untouched. Malformed, unsupported, unaligned or symlink inputs are rejected. watchOS content is deliberately omitted.
- Re-signing a decrypted output may still require adjusting entitlements; decryption alone does not guarantee the app or its services work when sideloaded.
- Copy, Share, Save and selectable reports are available in AppVault and the helper. Their signed-device behavior remains unverified.

## Verification

CI tests the actual helper builder with synthetic packages: encrypted-resource preservation, SINF replication, Watch omission, manifest verification, tamper detection, traversal rejection and missing-license rejection. CI separately compiles the real helper target, bundles its template into AppVault, compiles AppVault, and verifies package versions. No real user credentials or licensed packages are sent to CI.
