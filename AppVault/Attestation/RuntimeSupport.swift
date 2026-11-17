import Foundation
import CryptoKit
import WebKit
import SwiftUI

// Compatibility types for the reviewed, pinned upstream runtime adapter.
enum ToolError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let s) = self { return s }; return nil } }
enum AppText {
    static func text(_ value: String) -> String {
        let messages = ["正在验证请求":"Preparing Apple authentication", "准备本地环境":"Preparing local authentication", "验证请求":"Signing Apple request", "准备下载":"Preparing IPA authorization", "验证设备":"Verifying Store device", "复用本机验证组件":"Reusing local authentication", "加载验证组件":"Loading authentication components", "生成下载授权数据":"Generating IPA authorization", "完成设备安全验证":"Completing Store verification", "生成请求签名":"Signing request", "准备验证组件":"Preparing authentication", "本地验证环境加载超时，请重试。":"Authentication runtime loading timed out. Retry while AppVault stays open.", "验证已超过 3 分钟，已停止本次操作。请保持应用在前台后重试。":"Apple authentication timed out after three minutes. Keep AppVault open and retry."]
        return messages[value] ?? (value.unicodeScalars.contains { $0.value >= 0x3400 && $0.value <= 0x9fff } ? "Apple authentication runtime could not complete. Check the connection and retry." : value)
    }
}
struct StoreProofRecord: Codable, Equatable, Sendable { var identifier: String; var files: [String: String]; var updatedAt = Date() }
@MainActor enum StoreProofStore {
    static func load() -> [String: StoreProofRecord] {
        guard let data = try? VaultKeychain.read("store-proof"), let records = try? JSONDecoder().decode([String: StoreProofRecord].self, from: data) else { return [:] }
        return records
    }
    static func save(_ records: [String: StoreProofRecord]) throws { try VaultKeychain.write(JSONEncoder().encode(records), account: "store-proof") }
}
struct HTTPStatusError: Error { let code: Int }
private final class FixedAppleRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
// Only the three public setup endpoints accepted by LoopbackServer reach this
// transport. No Apple Account password/token is sent to any external relay.
final class HTTPClient: @unchecked Sendable {
    static let shared = HTTPClient()
    private let client = URLSession(configuration: .ephemeral, delegate: FixedAppleRedirects(), delegateQueue: nil)
    static func encodePlist(_ dict: [String: Any]) throws -> Data { try StoreProtocol.plist(dict) }
    func request(_ url: URL, method: String = "GET", body: Data? = nil, headers: [String: String] = [:], allowRedirects: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let allowed = ["https://s.mzstatic.com/sap/setupCert.plist", "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy", "https://auth.itunes.apple.com/auth/v1/otp/1.5/finish"]
        guard allowed.contains(url.absoluteString) else { throw HTTPStatusError(code: 403) }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 45
        request.setValue(StoreProtocol.userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await client.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw HTTPStatusError(code: 502) }
        guard (200..<300).contains(response.statusCode) else { throw HTTPStatusError(code: response.statusCode) }
        return (data, response)
    }
}
struct SigningRuntimeView: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
