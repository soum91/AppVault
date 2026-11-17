import Foundation
import Security
import SwiftUI

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

@MainActor final class StoreService: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var code = ""
    @Published var query = ""
    @Published var versionID = ""
    @Published var apps: [StoreApp] = []
    @Published var busy = false
    @Published var status = "Ready"
    @Published var error: String?
    @Published var needsCode = false
    @Published var signedIn = false
    @Published var downloads: [URL] = []
    @Published var exported: URL?
    private var client: DirectAppleStore?
    private var operation: Task<Void, Never>?
    private var lastFailure = "None"
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    var folder: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("IPAs", isDirectory: true) }
    var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "AppVault \(version) (\(build))\nDevice: \(UIDevice.current.model)\nOS: \(UIDevice.current.systemVersion)\nBackend: ApplePackage native SAP-signed login, URLSession IPA downloads\nJIT/emulator: none\nStage: \(status)\nLast failure: \(lastFailure)\nPhysical-device authentication and exports: unverified"
    }
    init() {
        do {
            var identity = try VaultKeychain.read("identity").flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if identity.isEmpty {
                var bytes = [UInt8](repeating: 0, count: 6)
                let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
                guard result == errSecSuccess else { throw VaultKeychain.failure(result) }
                bytes[0] = (bytes[0] | 2) & 0xfe
                identity = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
                try VaultKeychain.write(Data(identity.utf8), account: "identity")
            }
            let saved = try VaultKeychain.read("direct-state").map { try JSONDecoder().decode(DirectStoreState.self, from: $0) }
            client = DirectAppleStore(guid: identity, state: saved)
            signedIn = saved?.account != nil
            email = saved?.account?.email ?? ""
        } catch { fail(error) }
        refreshDownloads()
    }
    func refreshDownloads() {
        downloads = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "ipa" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func signIn() {
        guard !email.isEmpty, !password.isEmpty else { error = "Enter your Apple Account email and password."; return }
        let email = self.email, password = self.password, code = self.code
        run("Signing in directly with Apple") { client in
            try await client.login(email: email, password: password, code: code)
        }
    }
    func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        run("Searching App Store") { client in
            let apps = try await client.search(term)
            self.apps = apps
        }
    }
    func download(_ app: StoreApp) {
        guard signedIn else { error = "Sign in under Account before downloading."; return }
        let directory = folder, version = versionID.trimmingCharacters(in: .whitespacesAndNewlines)
        run("Requesting IPA") { client in
            let url = try await client.download(app, directory: directory, versionID: version) { [weak self] phase in
                Task { @MainActor in self?.status = phase }
            }
            self.refreshDownloads(); self.exported = url
        }
    }
    func signOut() {
        guard !busy else { return }
        run("Signing out") { client in
            try VaultKeychain.write(nil, account: "direct-state")
            try VaultKeychain.write(nil, account: "state") // Remove prior emulator sessions too.
            await client.signOut()
            self.email = ""; self.password = ""; self.code = ""; self.signedIn = false; self.needsCode = false
        }
    }
    func cancel() { operation?.cancel(); password = ""; code = ""; needsCode = false; status = "Cancellation requested" }
    private func run(_ phase: String, work: @escaping @MainActor (DirectAppleStore) async throws -> Void) {
        guard !busy else { return }
        guard let client else { error = "Secure storage is unavailable. Resolve the Keychain error before signing in."; return }
        busy = true; error = nil; status = phase
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "IPA download") { [weak self] in
            Task { @MainActor in self?.cancel(); self?.endBackgroundTask() }
        }
        operation = Task {
            defer { busy = false; operation = nil; endBackgroundTask(); if !needsCode { password = ""; code = "" } }
            do {
                try await work(client)
                try Task.checkCancellation()
                let state = await client.snapshot()
                try VaultKeychain.write(JSONEncoder().encode(state), account: "direct-state")
                signedIn = state.account != nil; needsCode = false; status = "Completed"
            } catch {
                if let failure = error as? StoreFailure, failure.code == "two_factor" { needsCode = true }
                // Persist challenge cookies without saving a password or code.
                if let state = try? JSONEncoder().encode(await client.snapshot()) {
                    do { try VaultKeychain.write(state, account: "direct-state") } catch { fail(error); return }
                }
                fail(error)
            }
        }
    }
    private func fail(_ problem: Error) {
        let message: String
        if problem is CancellationError || (problem as NSError).code == NSURLErrorCancelled {
            message = "Operation cancelled. [cancelled]"
        } else if let failure = problem as? StoreFailure {
            message = failure.localizedDescription
        } else {
            let issue = problem as NSError
            // Do not include arbitrary server bodies, URLs or account fields.
            message = "The operation failed (\(issue.domain), code \(issue.code)). Check your network, free storage and Keychain access."
        }
        lastFailure = message; error = message; status = "Failed"
    }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
}
