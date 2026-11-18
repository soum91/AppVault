import Foundation

/// Minimal local export failure type for the standalone privileged app.
/// No Apple Account, Store, WebKit or network code is linked into this target.
struct VaultFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
