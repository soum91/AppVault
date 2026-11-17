AppVault 0.4.0 (7), experimental build artifact

- Replaces the primary app-data browser with native Apple Account, App Store search, IPA download and saved-file sharing screens.
- Links majd/ipatool at b352566155a667d8aaeabaa7ecec4966080f92ab into the app process through a Go C archive. Uses upstream's pinned Unicorn 2.1.4 source, integrity check and iOS W^X patch.
- Checks executable-memory capability before sign-in. This backend requires JIT or a compatible jailbreak; worse_query alone is insufficient. No JIT enablement mechanism is included.
- Stores tokens and provisioning state in device-only Keychain storage. Strips the login password before persisting upstream account records. Uses a private random persistent device identity rather than reading a hardware address.
- Reports download byte progress and supports cancellation during runtime preparation and file transfer. Apple authentication requests may finish before cancellation takes effect.
- Apple DRM remains. This downloads Apple-authorized packages, not installed-app binary extraction.

Validation: password-stripping and credential-clearing fixtures run in CI before packaging; installed-version preflight and iOS compilation are required. Physical-device authentication, JIT compatibility, clipboard/export and IPA reinstallation are unverified. Artifact-only; do not update the FlareStore feed or publish as a working replacement until device testing succeeds.
