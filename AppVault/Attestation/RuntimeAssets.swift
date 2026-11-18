import Foundation
import CryptoKit

// Download immutable runtime assets on-device; do not redistribute extracted
// Apple libraries in AppVault's IPA. Every file is pinned and hash checked.
actor RuntimeAssets {
    private static let instance = RuntimeAssets()
    private var ready = false
    static let revision = "81dd1f747e71b31629979e2c1de0fe234fe7de39"
    static var directory: URL { VaultStorage.runtime.appendingPathComponent(revision, isDirectory: true) }
    nonisolated static var rootIfReady: URL? { FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.html").path) ? directory : nil }
    static func prepare(progress: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        try await instance.install(progress: progress)
    }
    private static let hashes: [String: String] = [
    "index.html": "2c8aa13604ee77ef315820239deadd9a6ee70668a39e334e4f6689cf38f7067f",
    "libCoreADI.so": "ece4ffa6bbe4239e8f0d4714da57e62ce5e3c581d19553a83d78ac897783b905",
    "libstoreservicescore.so": "d8be230df34c0044758d43e33a8dabd3236b9a4258c4d48cb366911224d52f68",
    "sap-signer.js": "5dc1f67bdd61e166ffa931df274ee3c0c94f73e5a5524f62c6a600a199cd24eb",
    "sap.wasm": "b7150bb4d31a03c1a813d310c0b5d7211be2510f7ee970b273f4fce7ea134015",
    "unicorn_x86.js": "a6733c9f2b2b01cba236f945419c70319edbf6a7fb2a0250d61d1b98ca7a0314",
    "wasm_exec.js": "0c949f4996f9a89698e4b5c586de32249c3b69b7baadb64d220073cc04acba14"
]
    private func install(progress: @escaping @Sendable (String) -> Void) async throws {
        if ready { progress("Authentication components already prepared"); return }
        try VaultStorage.ensureWritable(Self.directory, operation: "preparing authentication runtime")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        // Avoid the system's very long default resource timeout on stalled downloads.
        configuration.timeoutIntervalForRequest = 35
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let assets = Self.hashes.sorted(by: { $0.key < $1.key })
        for (index, asset) in assets.enumerated() {
            try Task.checkCancellation()
            let (name, digest) = asset
            progress("Checking authentication component \(index + 1)/\(assets.count): \(name)")
            let destination = Self.directory.appendingPathComponent(name)
            if let existing = try? Data(contentsOf: destination, options: .mappedIfSafe), Self.hash(existing) == digest { continue }
            progress("Downloading authentication component \(index + 1)/\(assets.count): \(name)")
            let url = URL(string: "https://raw.githubusercontent.com/mengangs/ipadn/" + Self.revision + "/iPadn-iOS/vendor/SAPRuntime/files/" + name)!
            // download(from:) needs a URLSession temporary-file container, which
            // a platform-signed rootless installation may not have. The pinned
            // auth resources are bounded and can safely be fetched in memory.
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw StoreProtocol.failure("runtime_download", "Authentication components could not be downloaded from the pinned source.") }
            guard Self.hash(data) == digest else { throw StoreProtocol.failure("runtime_integrity", "Authentication component integrity check failed for \(name). Sign-in was stopped.") }
            do { try data.write(to: destination, options: .atomic) }
            catch {
                let cause = error as NSError
                throw VaultStorageError(operation: "saving " + name, folder: Self.directory.path,
                                        domain: cause.domain, code: cause.code)
            }
            progress("Verified authentication component \(index + 1)/\(assets.count)")
        }
        ready = true
        progress("Authentication components ready")
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
