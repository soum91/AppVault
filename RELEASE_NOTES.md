# AppVault 0.6.2 (15) - useful authentication failures

Fixes the user-observed `AppVaultToolError code 0` message after local sign-in fails.

- Show AppVault's own human-readable `ToolError` explanation, rather than replacing it with a meaningless NSError domain/code.
- Distinguish WebKit local-signing script failures using their numeric error code while keeping raw JavaScript exception text, credentials, URLs, tokens and server response bodies out of dialogs and reports.
- Translate missing local signer address and empty signer results into actionable English.
- Retain the 0.6.1 stage-by-stage progress, pinned assets, timeouts and 0.6.0 rootless filesystem correction.

This is diagnostic error handling, not a bypass of Apple sign-in. No physical-device Apple Account login, 2FA success, IPA download or DRM decryption is claimed without device evidence. Open AppVault > Settings > Backend Report for the last failed stage.
