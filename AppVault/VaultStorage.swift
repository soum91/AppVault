import Foundation

/// Rootless apps installed under /var/jb/Applications may not receive a
/// writable app-data container when launched without a sandbox.
enum VaultStorage {
    static var isRootless: Bool {
        // An incorrectly signed rootless installation still needs a writable
        // data path, even if the privilege probe returns false.
        let installed = Bundle.main.bundleURL.path
        let resolved = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return AVHasDecryptionPrivileges() ||
            installed.hasPrefix("/var/jb/Applications/") ||
            (resolved.contains("/preboot/") && resolved.contains("/Applications/AppVault.app"))
    }
    static var base: URL {
        if isRootless {
            return URL(fileURLWithPath: "/var/mobile/Library/Application Support/com.soum91.appvault", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppVault", isDirectory: true)
    }
    static var runtime: URL { base.appendingPathComponent("AuthenticationRuntime", isDirectory: true) }
    static var exports: URL {
        if isRootless { return base.appendingPathComponent("Exports", isDirectory: true) }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var workspace: URL {
        if isRootless { return base.appendingPathComponent("Temporary", isDirectory: true) }
        return FileManager.default.temporaryDirectory
    }
    static func ensureWritable(_ folder: URL, operation: String) throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let probe = folder.appendingPathComponent(".appvault-write-check-" + UUID().uuidString)
            try Data([0x41]).write(to: probe, options: [.atomic])
            defer { try? fm.removeItem(at: probe) }
            guard try Data(contentsOf: probe) == Data([0x41]) else {
                throw CocoaError(.fileReadNoPermission)
            }
        } catch {
            let problem = error as NSError
            throw VaultStorageError(operation: operation, folder: folder.path,
                                    domain: problem.domain, code: problem.code)
        }
    }
}
struct VaultStorageError: LocalizedError {
    let operation: String
    let folder: String
    let domain: String
    let code: Int
    var errorDescription: String? {
        "AppVault cannot write its files during \(operation). Directory: \(folder). " +
        "Error \(domain) (\(code)). Reinstall or upgrade the rootless AppVault DEB in Sileo to repair mobile-owned application storage."
    }
}
