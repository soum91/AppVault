# AppVault 0.7.2 (25)

- Import an IPA through the system copy picker and stage a coordinated local copy before opening the ZIP. The rootless app lists installed-app export first and labels the stock helper separately.

- Keep an authorized IPA download independent of Keychain session saves. Skip redundant saves, keep a live session if persistence fails, and retain the original download error if the operation fails.
- Continue with an in-memory Store proof if the Keychain temporarily disallows interaction. Credentials and session data remain in the Keychain when persisted.
- Show separate progress for download authorization, the Store request, CDN transfer and final IPA validation. A cancellation preserves the last active stage in Backend Report.
- Run synthetic download authorization through the interpreter in CI. Actual IPA downloads on the iOS 16.1.1 device remain unverified.
