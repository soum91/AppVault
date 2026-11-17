# AppVault 0.4.2 (9) validation

0.4.1 returned unsigned HTTP 403. A SAP-only ApplePackage candidate passed unit tests but returned HTTP 204 in the live probe and was not released. The final candidate adds Store AMD provisioning and kbsync using pinned iPadn runtime 81dd1f747e71b31629979e2c1de0fe234fe7de39.

Observed live locally: authentication HTTP 200 with SP and no prior proof; local Store provisioning; authentication HTTP 200 with provisioned proof and a business authentication response. No real user credentials were used. This does not establish real-account login/2FA or downloads.

Required release gates: runtime component hashes and offline smoke tests, controlled live Store-proof acceptance, existing Store protocol fixtures, installed-version preflight and iOS device compilation.

Physical-device startup, real-account login/2FA, real IPA downloads, Copy/Share/Files export and reinstallation remain unverified. No JIT entitlement or jailbreak is required by the WebKit runtime.
