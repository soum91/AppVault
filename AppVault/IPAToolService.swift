import Foundation
import Security
import SwiftUI

struct StoreApp: Codable, Identifiable {
    let trackId: Int64
    let bundleId: String?
    let trackName: String?
    let version: String?
    let price: Double?
    var id: Int64 { trackId }
}
private struct BridgeReply: Decodable {
    let ok: Bool
    let error: String?
    let code: String?
    let email: String?
    let apps: [StoreApp]?
    let path: String?
    let state: [String: String]?
}
private enum VaultKeychain {
    static func read(_ account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.soum91.appvault.ipatool", kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw failure(status) }
        return item as? Data
    }
    static func write(_ data: Data?, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.soum91.appvault.ipatool", kSecAttrAccount as String: account]
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }
    static func failure(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Secure storage failed (\(status)). Sign-in state was not saved."])
    }
}

@MainActor final class IPAToolService: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var code = ""
    @Published var query = ""
    @Published var apps: [StoreApp] = []
    @Published var busy = false
    @Published var status = "Ready"
    @Published var error: String?
    @Published var needsCode = false
    @Published var signedIn = false
    @Published var capable = false
    @Published var downloads: [URL] = []
    @Published var exported: URL?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.soum91.appvault.ipatool", qos: .userInitiated)
    private var state: [String: String] = [:]
    private var identity = ""
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    var folder: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("IPAs", isDirectory: true) }
    init() {
        refreshCapability()
        do {
            if let data = try VaultKeychain.read("state") { state = try JSONDecoder().decode([String: String].self, from: data) }
            if let data = try VaultKeychain.read("identity"), let value = String(data: data, encoding: .utf8) { identity = value }
            if identity.isEmpty {
                var bytes = [UInt8](repeating: 0, count: 6)
                let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
                guard result == errSecSuccess else { throw VaultKeychain.failure(result) }
                bytes[0] = (bytes[0] | 2) & 0xfe
                identity = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
                try VaultKeychain.write(Data(identity.utf8), account: "identity")
            }
            signedIn = state["account"] != nil
        } catch { self.error = error.localizedDescription }
        refreshDownloads()
    }
    func refreshCapability() { capable = AVIPACanExecute() }
    func refreshDownloads() {
        downloads = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "ipa" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func signIn() {
        guard !email.isEmpty, !password.isEmpty else { error = "Enter your Apple Account email and password."; return }
        run("login", fields: ["Email": email, "Password": password, "Code": code])
    }
    func search() { guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }; run("search", fields: ["Term": query]) }
    func download(_ app: StoreApp) {
        guard let object = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(app)) else { return }
        run("download", fields: ["App": object, "Directory": folder.path])
    }
    func signOut() {
        guard !busy else { return }
        do { try VaultKeychain.write(nil, account: "state"); state = [:]; signedIn = false; password = ""; code = ""; apps = []; needsCode = false }
        catch { self.error = error.localizedDescription }
    }
    func cancel() { AVIPACancel(); status = "Cancellation requested" }
    private func run(_ operation: String, fields: [String: Any]) {
        guard !busy else { return }
        refreshCapability()
        guard capable else { error = "ipatool's authentication runtime needs JIT. iOS denied executable memory for AppVault. Enable JIT for this process or use a compatible jailbreak, then check again. worse_query does not itself grant JIT."; return }
        guard !identity.isEmpty else { error = "Secure device identity is unavailable. Resolve the Keychain error first."; return }
        var request = fields
        request["Operation"] = operation; request["Identity"] = identity; request["State"] = state
        guard let data = try? JSONSerialization.data(withJSONObject: request), let text = String(data: data, encoding: .utf8) else { return }
        busy = true; status = "Starting ipatool"; error = nil
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "IPA download") { [weak self] in
            Task { @MainActor in self?.cancel(); self?.endBackgroundTask() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let pointer = AVIPAStatus(); defer { AVIPAFree(pointer) }
                guard let pointer, let data = String(cString: pointer).data(using: .utf8), let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                self.status = payload["phase"] as? String ?? "Working"
                if let bytes = payload["bytes"] as? Double, bytes > 0 { self.status += " · " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
            }
        }
        // No request, password, token, or raw bridge response is logged.
        queue.async { [weak self] in
            let pointer = text.withCString { AVIPARun($0) }
            let result = pointer.map { Data(String(cString: $0).utf8) }
            AVIPAFree(pointer)
            Task { @MainActor in self?.finish(result, operation: operation) }
        }
    }
    private func finish(_ data: Data?, operation: String) {
        timer?.invalidate(); timer = nil; busy = false; endBackgroundTask()
        defer { if !needsCode { password = ""; code = "" } }
        guard let data, let reply = try? JSONDecoder().decode(BridgeReply.self, from: data) else { error = "The ipatool bridge returned an invalid response."; return }
        do {
            if let next = reply.state {
                try VaultKeychain.write(JSONEncoder().encode(next), account: "state")
                state = next
            }
        } catch { self.error = error.localizedDescription; return }
        signedIn = state["account"] != nil
        needsCode = reply.code == "two_factor"
        if reply.ok {
            status = "Completed"
            if let apps = reply.apps { self.apps = apps }
            if let path = reply.path { refreshDownloads(); exported = URL(fileURLWithPath: path) }
        } else {
            // Do not display raw server errors that could echo account fields.
            error = needsCode ? "Apple requires a verification code. Enter it below and sign in again." : reply.code == "license_required" ? "This Apple Account has no license for this app. Get it in the App Store first, then retry." : "Apple authentication or the IPA download failed. ipatool returned an error; no successful backup is claimed. Check your account and connection, then retry."
            status = "Failed"
        }
    }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
}
