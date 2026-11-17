# AppVault 0.5.0 (12)

Adds **IPAs > Decrypt Installed Apps** and a separate rootless jailbreak DEB. Select an installed user app, copy its app bundle, decrypt supported encrypted arm64 Mach-O slices with the device's FairPlay service, verify all copied binaries, and package `Payload/<App>.app` as an IPA. Includes nested frameworks and extensions; any unsupported or failed binary aborts the export and reports its failure. Original installed apps and earlier exports remain untouched.

The normal IPA keeps its limited entitlements and saves encrypted Apple downloads. Use the jailbreak DEB on the jailbroken device containing the installed app and matching App Store license. This does not add arbitrary-file decryption on stock iOS. See DECRYPTION.md for implementation, limitations and research attribution.

Validation: C parser fixtures and installed-version preflight passed locally. CI runs parser/protocol/runtime checks and compiles/packages both assets. Actual decryption on a physical jailbroken device, entitlement acceptance and diagnostic Copy/Share/Save remain unverified. Exported apps still need suitable signing.
