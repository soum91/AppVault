import Foundation

// Minimal stand-ins for the AppVault types InProcessSAPRuntime.swift uses, so
// the same runtime source builds into the standalone signer helper.
enum ToolError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum AppText {
    static func text(_ key: String) -> String { key == "验证结果为空，请重试" ? "The signer returned an empty result; retry." : key }
}

enum RuntimeAssets {
    nonisolated(unsafe) static var directory = URL(fileURLWithPath: "/nonexistent", isDirectory: true)
}
