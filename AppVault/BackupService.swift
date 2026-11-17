import Foundation
import Combine
import UIKit
import Darwin
import ZIPFoundation

struct FileEntry: Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let directory: Bool
}
struct InstalledEntry: Identifiable {
    var id: String { bundleID }
    let name: String
    let bundleID: String
    let bundlePath: String?
    let dataPath: String?
}
struct VaultFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
final class BackupService: ObservableObject {
    @Published var entries: [FileEntry] = []
    @Published var apps: [InstalledEntry] = []
    @Published var path = "/var/mobile/Containers/Data/Application"
    @Published var busy = false
    @Published var status = "Ready"
    @Published var error: String?
    @Published var exported: URL?
    @Published var group = AVGroups().first ?? "group.com.soum91.appvault"
    private let queue = DispatchQueue(label: "appvault.files", qos: .userInitiated)

    func work(_ message: String, operation: @escaping () throws -> Void) {
        guard !busy else { return }
        busy = true
        status = message
        queue.async {
            do {
                try operation()
                DispatchQueue.main.async { self.busy = false; self.status = "Ready" }
            } catch {
                DispatchQueue.main.async {
                    self.busy = false
                    self.status = "Operation failed"
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func withAccess<T>(_ path: String, _ action: () throws -> T) throws -> T {
        let alternate = ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 && path.contains("/Containers/Shared/AppGroup")
        let handle = worse_query(path, group, alternate, false)
        // A directly readable path can still work when an extension is unavailable.
        if handle < 0 && !FileManager.default.isReadableFile(atPath: path) {
            let reason: String
            switch handle {
            case -1: reason = "The signed app has no accessible App Group. Preserve the application-groups entitlement when signing. Group: \(group)"
            case -2: reason = "Container manager functions are unavailable on this OS."
            case -5: reason = "Container manager rejected access to this path."
            case -6: reason = "The kernel refused a sandbox extension for this path."
            default: reason = "Access failed with code \(handle)."
            }
            throw VaultFailure(message: "\(reason)\n\(path)")
        }
        defer { if handle >= 0 { worse_query_release(handle) } }
        return try action()
    }

    func browse(_ destination: String) {
        let target = URL(fileURLWithPath: destination).standardizedFileURL.path
        if target == "/var/mobile/Containers/Data/Application" || target == "/private/var/mobile/Containers/Data/Application" { discoverData(); return }
        work("Opening folder…") {
            let rows = try self.withAccess(target) {
                try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: target), includingPropertiesForKeys: [.isDirectoryKey])
                    .map { url in
                        FileEntry(path: url.path, name: url.lastPathComponent,
                                  directory: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
                    }.sorted { a,b in a.directory == b.directory ? a.name.localizedStandardCompare(b.name) == .orderedAscending : a.directory }
            }
            DispatchQueue.main.async { self.path = target; self.entries = rows }
        }
    }

    func loadApps() {
        work("Locating LaunchServices database…") {
            let raw = AVDiscoverApps { message in
                DispatchQueue.main.async { self.status = message }
            }
            let rows = raw.map { item in
                InstalledEntry(name: item["localizedName"] as? String ?? "Application",
                               bundleID: item["bundleIdentifier"] as? String ?? UUID().uuidString,
                               bundlePath: nil,
                               dataPath: item["dataContainerURL"] as? String)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async { self.apps = rows }
            guard !rows.isEmpty else { throw VaultFailure(message: AVDiscoveryStatus()) }
        }
    }
    func cancelDiscovery() { AVDiscoveryCancel() }
    func discoverData() {
        work("Locating app data containers…") {
            let rows = AVDiscoverApps { message in
                DispatchQueue.main.async { self.status = message }
            }.compactMap { item -> FileEntry? in
                guard let path = item["dataContainerURL"] as? String else { return nil }
                return FileEntry(path: path, name: item["localizedName"] as? String ?? path, directory: true)
            }
            DispatchQueue.main.async { self.entries = rows; self.path = "/var/mobile/Containers/Data/Application" }
            if rows.isEmpty { throw VaultFailure(message: AVDiscoveryStatus()) }
        }
    }
    var report: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "AppVault \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))\niOS \(UIDevice.current.systemVersion)\n\(AVDiscoveryStatus())\n\(AVDiscoveryLog())"
    }

    func backup(_ source: String) {
        work("Copying and archiving \(URL(fileURLWithPath: source).lastPathComponent)…") {
            let fm = FileManager.default
            let sourceURL = URL(fileURLWithPath: source)
            let isApp = sourceURL.pathExtension.lowercased() == "app"
            let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }
            let folder = isApp ? staging.appendingPathComponent("Payload") : staging.appendingPathComponent("Backup")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let copiedRoot = folder.appendingPathComponent(sourceURL.lastPathComponent)
            try self.withAccess(source) {
                if isApp {
                    try fm.copyItem(at: sourceURL, to: copiedRoot)
                } else {
                    let canonical = sourceURL.standardizedFileURL.path.replacingOccurrences(of: "/private/var/", with: "/var/")
                    let parent = URL(fileURLWithPath: canonical).deletingLastPathComponent().path
                    let result = try AppDataCopy.copy(source: sourceURL, to: copiedRoot,
                        applicationContainer: parent == "/var/mobile/Containers/Data/Application")
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(result).write(to: staging.appendingPathComponent("backup-manifest.json"))
                }
            }
            let destination = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("\(sourceURL.deletingPathExtension().lastPathComponent)-\(Int(Date().timeIntervalSince1970)).\(isApp ? "ipa" : "zip")")
            do {
                try fm.zipItem(at: staging, to: destination, shouldKeepParent: false)
                // ZIPFoundation must be able to read its own central directory before export.
                _ = try Archive(url: destination, accessMode: .read)
            } catch {
                try? fm.removeItem(at: destination)
                throw error
            }
            guard fm.fileExists(atPath: destination.path) else { throw VaultFailure(message: "No archive was produced.") }
            DispatchQueue.main.async { self.exported = destination }
        }
    }
}
