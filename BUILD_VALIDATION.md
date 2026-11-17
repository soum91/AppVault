# AppVault 0.4.2 (9) verification status

The unsigned login in 0.4.1 returned HTTP 403 on the user's device. Version 0.4.2 replaces it with the complete native ApplePackage Authenticator, pinned at 391bfe6ee6598d73e4f94b88b38b50bd6f6ec67b, including request signing and retained verification-code state.

Required release gates are documented in the workflow: signing/handshake/authentication unit tests, controlled live signature acceptance, installed-version contract and iOS compilation. Build results must be read from the actual workflow, not inferred from this document.

No user password was supplied to this environment. Real-account login, 2FA delivery, actual downloads, clipboard/Share/Files exports and reinstallation remain unverified. The live probe can demonstrate signature acceptance; it cannot demonstrate a real user's login.
