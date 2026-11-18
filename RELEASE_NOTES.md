# AppVault 0.6.5 (18) - separate WebKit sign-in from privileged decryption

**Root cause demonstrated by the iOS 16.1.1 Dopamine report:** the privileged AppVault rootless app's `WKWebView` WebContent process terminates during attachment, before Apple Account login or 2FA. Multiple `WEB_CONTENT_EXIT` events persist after the 0.6.4 view and memory-lifecycle changes. Another 2FA form or a larger WebKit view cannot fix this.

**Architecture correction:** The rootless DEB now installs a standalone **AppVault Decryptor** app (`com.soum91.appvault.decryptor`) with the existing privileged installed-app scan, Mach-O decryption, verified IPA export, report, and file sharing. It deliberately does not link or launch `WKWebView`, the SAP runtime or the Apple Account login code. Its version/build are visible in the app.

The normal **AppVault IPA** (`com.soum91.appvault`) remains the separate sandboxed Apple Store search/sign-in/download and stock helper client. Install that IPA through an ordinary sideloader such as FlareStore or EmberSign, and install the rootless Decryptor DEB from the existing `soum91/tweaks` Sileo source. **Two icons are expected.** The versioned DEB replaces the former privileged AppVault.app icon; it does not remove a separately installed sandboxed AppVault IPA or erase AppVault's existing rootless export folder.

- Keeps the original rootless Debian package identity `com.soum91.appvault` so Sileo can upgrade installed users, but changes its app bundle to `AppVaultDecryptor.app`.
- Drops the iOS 16 WebKit login requirement from the privileged binary, avoiding the observed WebContent launch failure on that path.
- Retains account authorization through Apple's existing Store protocol in the normal IPA. No DRM, license or security validation has been bypassed.
- Adds a build-time regression gate that rejects accidental WebKit/Store dependencies in the rootless target.

**Limitations:** Successful sign-in on the stock IPA, actual decryption, FairPlay and IPA export still require real-device verification. This is a privilege-separated workaround, not proof that iOS 16's WebContent crash is fixed. The two apps do not automatically hand off downloaded IPAs or Apple Account sessions. Installed-app export is independent of AppVault's download feature. Re-signing or sideloading a downloaded encrypted App Store IPA does not decrypt it.
