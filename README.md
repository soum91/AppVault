# AppVault

Native iOS UI for IPA package downloads using the MIT-licensed [majd/ipatool](https://github.com/majd/ipatool) backend. The 0.4.0 integration is experimental and built as a GitHub Actions artifact, with no automatic release/feed promotion.

## Runtime requirement

The pinned backend emulates Apple authentication components through Unicorn. Its upstream iOS build is explicitly for jailbroken devices. AppVault embeds the backend, but it still requires executable memory. On stock iOS, working JIT must be enabled for AppVault; a signing entitlement or worse_query does not grant this capability. AppVault checks the required writable-to-executable memory transition before collecting a password. Passing that check is necessary, but does not prove full runtime compatibility.

Without JIT or a compatible jailbreak this backend cannot sign in or download. No desktop companion or private credential server is included. First use downloads and verifies the pinned Apple runtime assets through upstream code. Keep the app in the foreground. Cancellation is cooperative; some upstream authentication requests do not accept a context.

## Packages and accounts

AppVault downloads account-authorized IPA packages from Apple. It does not extract installed app bundles, decrypt DRM, restore app data, or promise sideloadability. Obtain licenses through the App Store first. Tokens/provisioning are saved in device-only Keychain storage. Passwords are stripped from stored account records and only retained in memory while completing a verification-code challenge. No extra root CA is used.

## Build

Use macOS, Xcode, Go 1.26.5, XcodeGen, ldid and CMake. Run `scripts/build-ipatool.sh`, `python3 scripts/check_version_ui.py`, `xcodegen generate`, then the xcodebuild command in `.github/workflows/ios-build.yml`. The build pins ipatool at `b352566155a667d8aaeabaa7ecec4966080f92ab` and uses its integrity-checked Unicorn 2.1.4 build/patch. Libraries are linked statically into the app, not launched as a child process. Upstream's MIT license is bundled during build; Unicorn retains its upstream license obligations.

## Validation status

CI checks the version contract and password/credential-clearing fixtures, then compiles a device IPA. Physical-device login, JIT, actual downloads, file exports and installation remain unverified. Do not describe a successful build as a verified authentication fix. Earlier 0.3.x builds were app-data backup experiments and do not satisfy IPA download requirements.
