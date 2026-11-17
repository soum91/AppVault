import Foundation

/// Copies app-owned data only. A failure reading user data aborts the backup.
enum AppDataCopy {
    static let metadataName = ".com.apple.mobile_container_manager.metadata.plist"
    struct Result: Codable {
        var copiedFiles = 0
        var copiedBytes: Int64 = 0
        var excluded: [String] = []
    }
    static func copy(source: URL, to destination: URL, applicationContainer: Bool) throws -> Result {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var result = Result()
        let sourceAttributes = try fm.attributesOfItem(atPath: source.path)
        guard sourceAttributes[.type] as? FileAttributeType == .typeDirectory else {
            throw NSError(domain: "AppVault.Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose an app data folder for backup."])
        }
        let children = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for child in children {
            if child.lastPathComponent == metadataName {
                result.excluded.append(child.lastPathComponent)
                continue
            }
            if applicationContainer && !["Documents", "Library"].contains(child.lastPathComponent) {
                result.excluded.append(child.lastPathComponent)
                continue
            }
            try copyItem(child, to: destination.appendingPathComponent(child.lastPathComponent),
                         relative: child.lastPathComponent, appData: applicationContainer, result: &result)
        }
        return result
    }
    private static func copyItem(_ source: URL, to destination: URL, relative: String,
                                 appData: Bool, result: inout Result) throws {
        let fm = FileManager.default
        if appData && relative == "Library/Caches" {
            result.excluded.append(relative)
            return
        }
        let attrs = try fm.attributesOfItem(atPath: source.path)
        let type = attrs[.type] as? FileAttributeType
        if type == .typeSymbolicLink {
            throw NSError(domain: "AppVault.Backup", code: 2, userInfo: [NSLocalizedDescriptionKey: "Backup stopped at symbolic link \(relative). No archive was completed."])
        }
        if type == .typeDirectory {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                try copyItem(child, to: destination.appendingPathComponent(child.lastPathComponent),
                             relative: relative + "/" + child.lastPathComponent, appData: appData, result: &result)
            }
        } else {
            do { try fm.copyItem(at: source, to: destination) }
            catch {
                throw NSError(domain: "AppVault.Backup", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Could not back up app data at \(relative): \(error.localizedDescription). No archive was completed.",
                    NSUnderlyingErrorKey: error
                ])
            }
            result.copiedFiles += 1
            result.copiedBytes += (attrs[.size] as? NSNumber)?.int64Value ?? 0
        }
    }
}
