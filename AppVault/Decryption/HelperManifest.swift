import Foundation
import CryptoKit

enum HelperPaths {
    static func safe(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.contains("\\") && !value.contains("\0") &&
        !value.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
    }
    static func hash(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var digest = SHA256()
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty { digest.update(data: chunk) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func files(_ root: URL) throws -> [URL] {
        var failure: Error?
        guard let sequence = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in failure = error; return false }) else {
            throw HelperFailure(message: "Cannot enumerate embedded payload")
        }
        var files: [URL] = []
        for case let url as URL in sequence {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw HelperFailure(message: "Bundle symlinks are unsupported") }
            if values.isRegularFile == true { files.append(url) }
        }
        if let failure { throw failure }
        return files
    }
}
struct HelperFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct HelperManifest: Codable {
    let schema: Int
    let appName: String
    let bundleID: String
    let displayName: String
    let hashes: [String: String]
    func verify(_ root: URL) throws {
        guard schema == 1, HelperPaths.safe(appName), !appName.contains("/"), appName.hasSuffix(".app"),
              HelperPaths.safe(bundleID), !bundleID.contains("/"), !hashes.isEmpty else { throw HelperFailure(message: "Invalid helper manifest") }
        let files = try HelperPaths.files(root)
        guard files.count == hashes.count else { throw HelperFailure(message: "Embedded payload file count changed during signing. Use the payload-preserving EmberSign build.") }
        for file in files {
            let path = String(file.path.dropFirst(root.path.count + 1))
            guard HelperPaths.safe(path), let expected = hashes[path], try HelperPaths.hash(file) == expected else {
                throw HelperFailure(message: "Embedded payload changed: \(path). The signer must preserve EmbeddedPayload as resources.")
            }
        }
    }
}
