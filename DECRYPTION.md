# Decrypted IPA export

Version 0.5.0 adds a separate installed-app export backend. The App Store download backend continues to save the original encrypted package.

## Install and use

On a rootless jailbroken iPhone (for example Dopamine on iOS 16), install `AppVault-0.5.0-rootless.deb` using the package manager. Open AppVault, select **IPAs > Decrypt Installed Apps > Find Installed Apps**, then select **Decrypt and Export IPA** for an installed app. Share the verified output or access it in AppVault's IPAs folder. Open the decryption report for actionable errors, Copy, Share and Save.

The matching App Store account/license must be present on that device. An app installed only on another phone is not a target. Installing the ordinary AppVault IPA with FlareStore does not grant jailbreak entitlements. Stock iOS cannot use this installed-app backend. The jailbreak DEB is an app package, not an injected tweak, and remains in the AppVault repository.

## Implementation and boundaries

- A distinct package signs the existing app binary with platform, no-sandbox and AppBundles access entitlements. The normal IPA retains its original limited entitlements.
- Installed user apps are enumerated from `/var/containers/Bundle/Application`, not data containers. The original app is copied into a private temporary `Payload` directory and is never modified.
- An original C backend parses thin/FAT 64-bit Mach-O files and walks encryption commands. It uses the system `mremap_encrypted` interface with cryptid=2, then fault-safe `vm_read_overwrite` on each page. It executes no target app code and has no tweak injection or remote decryption service.
- Only after every encrypted page has been read and the encrypted bytes have changed does it clear the copied slice's cryptid. Every regular output file is checked again, including frameworks and app extensions. Failure aborts packaging, removes the attempted IPA, and retains the diagnostic. Earlier exports are not overwritten.
- Only little-endian 64-bit arm64 encrypted slices aligned to the device page size are supported. Unsupported or malformed Mach-O files fail explicitly. Bundle symlinks are rejected rather than left unchecked. watchOS binaries or other architectures may prevent export. No output is labelled successful while an encrypted slice remains.
- No executable target, sandbox permissions, FairPlay license or key is invented. A matching license and working system decryption service remain necessary. An exported IPA still needs suitable signing for installation, and app services/entitlements may not transfer.

## Validation

C parser fixtures exercise plaintext/encrypted files, malformed commands, range overflow, truncation and FAT overlap. Non-Apple fixtures verify that failure never clears the encryption marker. CI compiles the actual iOS backend and packages the jailbreak app. These checks do not establish device decryption compatibility.

**Physical-device decryption, entitlement acceptance and diagnostic Copy/Share/Save remain unverified.** In particular, this is not a claim that mremap-based decryption works on every Dopamine/OS build. If the OS rejects the mapping or page-in, the report includes its errno or Mach return code and no completed IPA is published.

## Research references

The public protocol/mechanism was checked against:
- https://github.com/JohnCoates/flexdecrypt (disk-backed FairPlay mapping)
- https://github.com/NyaMisty/fouldecrypt (jailbreak decryption tools)
- https://github.com/donato-fiore/TrollDecrypt (installed-app export, including extensions)
- https://github.com/morzelowski/FairPlayed (cryptid=2 read-only mapping, license/path constraints)

No source from these projects is vendored in this backend. Their names identify references, not authorship or endorsement of AppVault.
