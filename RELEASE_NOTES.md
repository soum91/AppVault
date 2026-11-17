AppVault 0.4.1 (8): native direct Apple Store client

- Removes the Go archive, Unicorn emulator, JIT capability gate and Apple framework asset downloads introduced in 0.4.0.
- Implements Apple login with native URLSession HTTPS using the DLiPA-observed Configurator request format, live bag endpoint discovery, token-only Keychain account storage and persisted session cookies.
- Handles redirects through case-insensitive header lookup, relative URL resolution, a five-hop limit and validated Apple HTTPS destinations. Does not reproduce DLiPA's exact-case Location lookup.
- Keeps search, account sign-in, verification-code submission, IPA download, optional external version ID and native IPA sharing in AppVault. Public search works before login.
- Validates the downloaded bundle, adds supplied Apple SINF license data and iTunes metadata to the IPA, and only lists the file as saved after packaging completes. Downloaded packages remain protected by Apple's DRM.
- Preserves redacted diagnostics with verified Copy, Share and plain-text Files export. Passwords and verification codes are never written to account storage.

Validation: protocol fixtures cover redirect host boundaries, XML escaping and payload keys, header casing, token-only account encoding, explicit HTTP 403 rejection, 2FA challenge handling, SINF path traversal and CDN host validation. CI also checks installed-version metadata and compiles the device app. Physical-device Apple sign-in, actual IPA downloads, clipboard and Files export remain unverified.

Important limitation: no JIT or jailbreak is required by this native implementation. However, Apple's service can reject unsigned Store login with HTTP 403. This build reports that rejection and does not claim to bypass it or guarantee a working account login. An Apple Account app-specific password is not a substitute for this Store login protocol.
