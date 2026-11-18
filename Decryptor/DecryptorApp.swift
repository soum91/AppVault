import SwiftUI

/// The rootless package must not host Apple's Store sign-in WebKit process.
/// Account sign-in and IPA downloads run in the separately signed/sandboxed
/// AppVault IPA. This privileged utility only exports apps already installed.
@main
struct AppVaultDecryptorApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DecryptionView()
            }
        }
    }
}
