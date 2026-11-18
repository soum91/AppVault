# AppVault 0.6.3 (16) - trusted-device code entry on iOS 16

The rootless jailbreak package and stock IPA use the same Store authentication implementation. This release makes the already-supported manual six-digit Apple Account verification-code path accessible on both before an Apple-issued challenge is displayed.

- Add **Use a Verification Code** to the Account screen, allowing entry of a code obtained directly from an existing trusted Apple device.
- Preserve Apple's original authentication requirements: when Apple issues an HSA2 session, continue to request a trusted-device approval and verify the code through that session.
- When no HSA2 session exists, submit the code using the existing Store protocol password-plus-code attempt, without sending it to any third-party server.
- Validate the code format locally, clear it when the manual field is dismissed or the operation is cancelled, and preserve the existing device-only Keychain session rules.
- Add a regression gate for the opt-in manual-code interface, server-issued approval session checks, and the pre-existing code-submission path.

**Limits:** This does not programmatically force Apple to generate a trusted-device push notification when Apple has not issued a verification session. The 0.6.0 device report showed Store bag HTTP 200 but no authenticated-login response, so a failure of the local WebKit/SAP signer can still block sign-in before 2FA. The stock IPA and rootless DEB share this signer. Physical-device login and IPA downloads remain unverified.
