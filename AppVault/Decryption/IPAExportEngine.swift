import Foundation
import ZIPFoundation

struct IPAExportFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Read-only source may be an installed user app or resources embedded in our own helper.
enum IPAExportEngine {
    static func export(source: URL, appName: String, identifier: String, folder: URL,
                       progress: (String) -> Void) throws -> URL {
        let fm = FileManager.default
        guard appName.hasSuffix(".app"), HelperPaths.safe(appName), !appName.contains("/"),
              HelperPaths.safe(identifier), !identifier.contains("/") else {
            throw IPAExportFailure(message: "Invalid output bundle name")
        }
        let work = fm.temporaryDirectory.appendingPathComponent("export-" + UUID().uuidString)
        var attempted: URL?
        defer { try? fm.removeItem(at: work) }
        do {
            let payload = work.appendingPathComponent("Payload", isDirectory: true)
            let destination = payload.appendingPathComponent(appName, isDirectory: true)
            try fm.createDirectory(at: payload, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: destination)
            guard let info = NSDictionary(contentsOf: source.appendingPathComponent("Info.plist")) as? [String: Any],
                  let executable = info["CFBundleExecutable"] as? String,
                  !executable.contains("/"), fm.isReadableFile(atPath: source.appendingPathComponent(executable).path) else {
                throw IPAExportFailure(message: "Installed app has no readable main executable")
            }
            var enumerationError: Error?
            guard let items = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in enumerationError = error; return false }) else {
                throw IPAExportFailure(message: "Cannot enumerate installed bundle")
            }
            var binaries = 0, decrypted = 0
            for case let binary as URL in items {
                let values = try binary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                var detail = [CChar](repeating: 0, count: 512)
                let encrypted = AVInspectMachO(binary.path, &detail, detail.count)
                guard encrypted >= 0 else { throw IPAExportFailure(message: "\(binary.lastPathComponent): \(String(cString: detail))") }
                guard encrypted > 0 else { continue }
                let relative = String(binary.path.dropFirst(source.path.count + 1))
                let target = destination.appendingPathComponent(relative)
                progress("Decrypting \(relative)")
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
                let count = AVDecryptMachO(binary.path, target.path, &detail, detail.count)
                guard count == encrypted else { throw IPAExportFailure(message: "\(relative): \(String(cString: detail))") }
                guard AVInspectMachO(target.path, &detail, detail.count) == 0 else { throw IPAExportFailure(message: "Verification failed: encrypted slices remain in \(relative)") }
                binaries += 1; decrypted += Int(count)
                progress("Verified \(relative): \(count) decrypted slice(s)")
            }
            if let enumerationError { throw enumerationError }
            // Re-scan every regular file, including extensions and nested frameworks.
            var verificationError: Error?
            guard let verify = fm.enumerator(at: destination, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in verificationError = error; return false }) else { throw IPAExportFailure(message: "Cannot verify output bundle") }
            for case let binary as URL in verify {
                let values = try binary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true { throw IPAExportFailure(message: "Bundle symlinks are unsupported; export rejected to avoid unchecked binaries") }
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                var detail = [CChar](repeating: 0, count: 512)
                guard AVInspectMachO(binary.path, &detail, detail.count) == 0 else { throw IPAExportFailure(message: "Output verification failed for \(binary.lastPathComponent)") }
            }
            if let verificationError { throw verificationError }
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            // Never overwrite an earlier export or an encrypted App Store download.
            let out = folder.appendingPathComponent("\(identifier)-decrypted-\(UUID().uuidString.prefix(8)).ipa")
            attempted = out
            progress("Packaging verified IPA")
            try fm.zipItem(at: payload, to: out, shouldKeepParent: true, compressionMethod: .deflate)
            let archive = try Archive(url: out, accessMode: .read)
            guard archive["Payload/\(appName)/Info.plist"] != nil else {
                throw IPAExportFailure(message: "IPA archive verification failed")
            }

            progress("Complete: \(binaries) binaries / \(decrypted) decrypted slices; every output binary checked")
            return out
        } catch {
            if let attempted { try? fm.removeItem(at: attempted) }
            throw error
        }
    }
}
