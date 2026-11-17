AppVault 0.4.2 (9): native SAP-signed Apple Account login

- Replaces the unsigned login request that returned HTTP 403 in 0.4.1 with ApplePackage's complete native Authenticator, pinned to 391bfe6ee6598d73e4f94b88b38b50bd6f6ec67b.
- Performs fresh SAP certificate/setup exchanges and sends X-Apple-ActionSignature over the exact authentication body. Signing uses native Swift/C arithmetic and OpenSSL; no emulator, JIT, private Apple framework or credential relay is involved.
- Retains the same Authenticator, signing stream, endpoint and cookies when a verification code is submitted. Starting a new sign-in or changing the account establishes a new session.
- Converts a successful library account to AppVault's token-only Keychain model. The library's Account object, which contains a password, is never serialized; the password is cleared before mapping. Successful cookies, DSID, storefront and pod are passed to the existing IPA download path.
- Maps signed-request rejection, SAP setup failure and invalid verification-code failures to distinct redacted errors. The app no longer describes its login as unsigned.
- Bundles ApplePackage's MIT notice and preserves the existing package identifier, icon and Keychain service.

Release checks: installed-version preflight, existing direct Store fixtures, pinned upstream signing/handshake/authentication unit tests, controlled live signed/unsigned/corrupted authentication checks, and device compilation must all pass before publication. The live probe uses invented credentials: it verifies whether Apple accepts the signature, not a real account login or code delivery.

Physical-device login with the user's account, actual IPA downloads and native export remain unverified. Apple account restrictions, invalid credentials and account-specific challenges can still prevent login. Apple DRM remains.
