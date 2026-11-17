import Foundation
import CryptoKit

// Download immutable runtime assets on-device; do not redistribute extracted
// Apple libraries in AppVault's IPA. Every file is pinned and hash checked.
actor RuntimeAssets {
    private static let instance = RuntimeAssets()
    private var ready = false
    static let revision = "81dd1f747e71b31629979e2c1de0fe234fe7de39"
    static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AuthenticationRuntime/" + revision, isDirectory: true) }
    nonisolated static var rootIfReady: URL? { FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.html").path) ? directory : nil }
    static func prepare() async throws { try await instance.install() }
    private static let hashes: [String: String] = [
    "index.html": "2c8aa13604ee77ef315820239deadd9a6ee70668a39e334e4f6689cf38f7067f",
    "libCoreADI.so": "ece4ffa6bbe4239e8f0d4714da57e62ce5e3c581d19553a83d78ac897783b905",
    "libstoreservicescore.so": "d8be230df34c0044758d43e33a8dabd3236b9a4258c4d48cb366911224d52f68",
    "sap-signer.js": "5dc1f67bdd61e166ffa931df274ee3c0c94f73e5a5524f62c6a600a199cd24eb",
    "sap.wasm": "b7150bb4d31a03c1a813d310c0b5d7211be2510f7ee970b273f4fce7ea134015",
    "unicorn_x86.js": "a6733c9f2b2b01cba236f945419c70319edbf6a7fb2a0250d61d1b98ca7a0314",
    "wasm_exec.js": "0c949f4996f9a89698e4b5c586de32249c3b69b7baadb64d220073cc04acba14"
]
    private func install() async throws {
        if ready { return }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for (name, digest) in Self.hashes.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            let destination = Self.directory.appendingPathComponent(name)
            if let existing = try? Data(contentsOf: destination, options: .mappedIfSafe), Self.hash(existing) == digest { continue }
            let url = URL(string: "https://raw.githubusercontent.com/mengangs/ipadn/" + Self.revision + "/iPadn-iOS/vendor/SAPRuntime/files/" + name)!
            let (temporary, response) = try await session.download(from: url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw StoreProtocol.failure("runtime_download", "Authentication components could not be downloaded from the pinned source.") }
            let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
            guard Self.hash(data) == digest else { throw StoreProtocol.failure("runtime_integrity", "Authentication component integrity check failed. Sign-in was stopped.") }
            try data.write(to: destination, options: .atomic)
        }
        ready = true
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
