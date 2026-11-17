# AppVault 0.4.4 (11) validation status

The reported device failure was HTTP 406, with no response headers/body supplied. Its precise cause is not established. Source inspection found a restrictive XML-only Accept header, status-first rejection of structured challenge bodies, and no trusted-device prompt request path. This version addresses those gaps without treating every 406 as 2FA.

Required gates: protocol fixtures for verification sessions and HTTP 406, pinned runtime integrity/smoke tests, live SAP/Store-proof check, installed-version preflight and iOS compilation.

Real-account approval notification delivery, code verification, login, IPA downloads, clipboard/Share/Files export and installation remain unverified on a signed physical device. No user password or verification code was supplied to this environment.
