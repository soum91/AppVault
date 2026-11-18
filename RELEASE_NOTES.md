# AppVault 0.6.1 (14) - authentication progress and finite runtime download timeouts

This release addresses the observed indefinite-looking **Signing in directly with Apple** state on a Dopamine / iOS 16 device.

- Show the actual authentication stage during Store endpoint discovery, first-run component verification/download, local signing service startup, WebKit authentication and Apple Store session negotiation.
- Report which of the seven pinned runtime components is being checked or downloaded. Keep the existing SHA-256 pinning, HTTPS validation and device-only credentials.
- Bound each runtime component's network request/resource wait rather than inheriting the system's long default resource timeout, and surface an actionable error when a download stalls.
- Include the failing stage in the Settings > Backend Report without recording credentials, cookies, raw server responses or Apple Account identifiers.
- Retain the 0.6.0 rootless mobile-owned storage fix, installed-app export and stock helper functions.

**Limitations:** This is a diagnosability and bounded-network-wait correction. The photo did not identify the precise blocked stage. Physical-device Apple Account login, second-factor approval, IPA download and FairPlay decryption still require validation. A successful GitHub CI build is not evidence of a successful sign-in on iOS 16. Existing verified runtime components remain cached after upgrade.

Source: https://github.com/soum91/AppVault
