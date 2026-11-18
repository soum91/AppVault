import SwiftUI

/// Rootless DEB app. It hosts the full AppVault UI: Apple Account sign-in and
/// IPA downloads plus privileged installed-app export. It is built with
/// APPVAULT_ROOTLESS, so no WebKit is linked: WebContent exits at spawn for
/// this platform-signed app on iOS 16, and sign-in instead runs the pinned SAP
/// runtime in-process with JavaScriptCore (dynamic-codesigning entitlement).
@main
struct AppVaultDecryptorApp: App {
    var body: some Scene {
        WindowGroup { BackupHomeView() }
    }
}
