# AppVault 0.4.1 (8) validation status

This native implementation replaces the 0.4.0 emulator build. The old 0.4.0 success record does not validate this new code.

Required CI: installed-version preflight, direct Store protocol fixtures, existing legacy data-copy fixtures, iOS device compilation and IPA metadata verification.

Physical-device startup, Apple account login/2FA, actual IPA download, clipboard/share/Files export and reinstallation remain unverified. Apple may reject unsigned authentication with HTTP 403. The app has no JIT dependency and does not claim to overcome Apple's server-side requirements.
