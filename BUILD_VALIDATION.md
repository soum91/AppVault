# AppVault 0.4.2 (9) verification

Source: ce0fc0eafeb728d2a579ad9f988fce1c2690581d. Successful build: https://github.com/soum91/AppVault/actions/runs/44029967141.

The unsigned 0.4.1 request returned HTTP 403. A SAP-only candidate passed unit tests but returned empty HTTP 204 in a controlled live probe and was blocked from release. The released implementation adds Store AMD provisioning and kbsync using pinned iPadn runtime 81dd1f747e71b31629979e2c1de0fe234fe7de39.

Passed gates: installed-version preflight, existing protocol/copy fixtures, pinned runtime integrity and smoke tests, live Store-proof exchange, iOS compilation, packaging, release publication and FlareStore update. The live exchange received HTTP 200/SP without proof, provisioned locally, then received HTTP 200 with a normal business authentication result and proof attached. No real account credentials were supplied. Kbsync is wired into ent/download; an actual account-authorized IPA download was not exercised.

Downloaded and inspected the public release IPA: com.soum91.appvault, version 0.4.2, build 9, assigned AppIcon. ATS allows local networking only; no arbitrary-load or certificate-trust bypass. No .so or sap.wasm is bundled; runtime files are downloaded on-device and checked against pinned hashes. IPA is 491,121 bytes, SHA-256 5143ed3b3db2a1e2d879be0519fecd6d659260f9c377365f858f562a8468671b. FlareStore reports 0.4.2 (9).

Not verified: physical-device startup/WebKit execution, real-account login/2FA, real IPA downloads, clipboard/Share/Files exports or reinstallation. No user-enabled JIT or jailbreak is required. The proof-acceptance check establishes the protocol milestone, not successful user login.
