import Foundation
import ZIPFoundation

enum HelperPreparation {
    static func prepare(ipa: URL, template: URL, folder: URL, workspace: URL? = nil, progress: (String) -> Void) throws -> URL {
        let fm = FileManager.default
        let work = (workspace ?? fm.temporaryDirectory).appendingPathComponent("stock-helper-" + UUID().uuidString)
        var attempted: URL?
        defer { try? fm.removeItem(at: work) }
        do {
            progress("Validating IPA paths")
            let archive = try Archive(url: ipa, accessMode: .read)
            var total: UInt64 = 0
            var paths = Set<String>()
            for entry in archive {
                let name = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
                guard HelperPaths.safe(name), entry.type != .symlink, paths.insert(name).inserted else {
                    throw HelperFailure(message: "Unsafe, duplicate or symlink IPA entry")
                }
                guard entry.uncompressedSize <= 40 * 1024 * 1024 * 1024 - total else { throw HelperFailure(message: "IPA exceeds 40 GB extraction limit") }
                total += entry.uncompressedSize
                guard paths.count <= 250_000 else { throw HelperFailure(message: "IPA has too many entries") }
            }
            let extracted = work.appendingPathComponent("input")
            let helperRoot = work.appendingPathComponent("helper")
            try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
            try fm.createDirectory(at: helperRoot, withIntermediateDirectories: true)
            progress("Extracting encrypted package")
            try fm.unzipItem(at: ipa, to: extracted)
            let candidates = try fm.contentsOfDirectory(at: extracted.appendingPathComponent("Payload"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
            guard candidates.count == 1, let app = candidates.first,
                  let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")) as? [String: Any],
                  let id = info["CFBundleIdentifier"] as? String, HelperPaths.safe(id), !id.contains("/"),
                  let executable = info["CFBundleExecutable"] as? String, HelperPaths.safe(executable), !executable.contains("/"),
                  fm.isReadableFile(atPath: app.appendingPathComponent(executable).path) else { throw HelperFailure(message: "IPA must contain exactly one valid iOS app") }
            progress("Preparing unsigned helper")
            try fm.unzipItem(at: template, to: helperRoot)
            let helper = helperRoot.appendingPathComponent("Payload/AppVaultDecrypt.app")
            guard fm.isReadableFile(atPath: helper.appendingPathComponent("AppVaultDecrypt").path) else { throw HelperFailure(message: "Bundled helper template is missing") }
            let embedded = helper.appendingPathComponent("EmbeddedPayload", isDirectory: true)
            try fm.createDirectory(at: embedded, withIntermediateDirectories: true)
            let target = embedded.appendingPathComponent("Target", isDirectory: true)
            // Resource directory, deliberately without .app suffix. Never execute the target.
            try fm.moveItem(at: app, to: target)
            if fm.fileExists(atPath: target.appendingPathComponent("Watch").path) { try fm.removeItem(at: target.appendingPathComponent("Watch")) }
            var licensePaths = ["SC_Info/\(executable).sinf"]
            let manifestURL = target.appendingPathComponent("SC_Info/Manifest.plist")
            if let manifest = NSDictionary(contentsOf: manifestURL) as? [String: Any] {
                licensePaths = (manifest["SinfPaths"] as? [String]) ?? licensePaths
                guard licensePaths.allSatisfy(HelperPaths.safe) else { throw HelperFailure(message: "Invalid SINF paths") }
                guard let first = licensePaths.first, fm.isReadableFile(atPath: target.appendingPathComponent(first).path) else { throw HelperFailure(message: "No matching App Store SINF license in IPA") }
                for path in manifest["SinfReplicationPaths"] as? [String] ?? [] {
                    guard HelperPaths.safe(path) else { throw HelperFailure(message: "Unsafe SINF replication path") }
                    if path.hasPrefix("Watch/") { continue }
                    let out = target.appendingPathComponent(path)
                    if !fm.fileExists(atPath: out.path) {
                        try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                        // Materialize an independent license resource for nested bundles.
                        try Data(contentsOf: target.appendingPathComponent(first)).write(to: out, options: .atomic)
                    }
                }
            }
            guard !licensePaths.isEmpty, licensePaths.contains(where: { fm.isReadableFile(atPath: target.appendingPathComponent($0).path) }) else { throw HelperFailure(message: "The IPA has no App Store license. Download an account-authorized package first.") }
            progress("Recording encrypted payload integrity")
            var hashes: [String: String] = [:]
            for file in try HelperPaths.files(target) {
                hashes[try HelperPaths.relativePath(file, under: target)] = try HelperPaths.hash(file)
            }
            let display = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? id
            let record = HelperManifest(schema: 1, appName: app.lastPathComponent, bundleID: id, displayName: display, hashes: hashes)
            try PropertyListEncoder().encode(record).write(to: helper.appendingPathComponent("AppVaultHelper.plist"), options: .atomic)
            let helperInfoURL = helper.appendingPathComponent("Info.plist")
            guard var helperInfo = NSDictionary(contentsOf: helperInfoURL) as? [String: Any], helperInfo["CFBundleIdentifier"] as? String == "com.soum91.appvault.decrypthelper" else { throw HelperFailure(message: "Invalid helper template identity") }
            helperInfo["CFBundleDisplayName"] = "Decrypt " + String(display.prefix(24))
            helperInfo["AppVaultStockHelper"] = true
            let plist = try PropertyListSerialization.data(fromPropertyList: helperInfo, format: .xml, options: 0)
            try plist.write(to: helperInfoURL, options: .atomic)
            for name in ["_CodeSignature", "embedded.mobileprovision"] {
                let url = helper.appendingPathComponent(name)
                if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            }
            try record.verify(target)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let output = folder.appendingPathComponent("AppVault-Decrypt-\(id)-\(UUID().uuidString.prefix(8)).ipa")
            attempted = output
            progress("Packaging helper for signing")
            try fm.zipItem(at: helperRoot.appendingPathComponent("Payload"), to: output, shouldKeepParent: true, compressionMethod: .deflate)
            return output
        } catch {
            if let attempted { try? fm.removeItem(at: attempted) }
            throw error
        }
    }
}
