AppVault 0.4.4 (11): account-bound verification sessions

- Clears a pending trusted-device verification context when signing in with a different account, preventing reuse of the preceding account's approval session.
- Corrects diagnostics to identify the local WebKit/WASM authentication runtime and distinguish it from user-enabled JIT, which is not required.
- Retains 0.4.3's broader Accept header, structured challenge parsing before HTTP-error rejection, session creation, trusted-device approval requests, code verification and redacted response traces. A bare HTTP 406 is not treated as evidence of two-factor authentication.

Validation: the verification-session fixtures, runtime integrity/smoke checks, live Store-proof acceptance and iOS compilation remain mandatory. 0.4.3 passed those checks before this follow-up. Real-account notification delivery, code verification, login, IPA download and exports remain unverified on a physical device. A notification request accepted by Apple does not prove that a trusted device displayed it.
