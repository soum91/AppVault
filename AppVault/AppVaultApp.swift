import SwiftUI
import Darwin

@main
struct AppVaultApp: App {
    init() {
        // Rootless DEB only: JavaScriptCore reads JSC_* options from the
        // environment when it first initializes. On Dopamine/iOS 16.1.1 it had
        // JIT (dynamic-codesigning, CS_DEBUGGED, its JIT region allocated) but
        // left WebAssembly undefined, so the in-process signer could not run.
        // Set these before any JSContext exists.
        if VaultStorage.isRootless {
            setenv("JSC_useJIT", "true", 1)
            setenv("JSC_useWebAssembly", "true", 1)
        }
    }
    var body: some Scene {
        WindowGroup { BackupHomeView() }
    }
}
