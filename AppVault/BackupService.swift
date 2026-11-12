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
        work("Finding installed applications…") {
            let rows = AVInstalledApps().map { raw in
                InstalledEntry(name: raw["localizedName"] as? String ?? raw["bundleIdentifier"] as? String ?? "Application",
                               bundleID: raw["bundleIdentifier"] as? String ?? UUID().uuidString,
                               bundlePath: raw["bundleURL"] as? String,
                               dataPath: raw["dataContainerURL"] as? String)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard !rows.isEmpty else { throw VaultFailure(message: "Installed-app enumeration returned no results. Use Browse or Discover Data Folders.") }
            DispatchQueue.main.async { self.apps = rows }
        }
    }

    func discoverData() {
        work("Discovering data folders. This can take several minutes…") {
            let baseline = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data([0]).write(to: baseline)
            defer { try? FileManager.default.removeItem(at: baseline) }
            let attrs = try FileManager.default.attributesOfItem(atPath: baseline.path)
            let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            let found = pathleak("/var/mobile/Containers/Data/Application", inode) ?? []
            let rows = found.map { FileEntry(path: $0, name: URL(fileURLWithPath: $0).lastPathComponent, directory: true) }
            DispatchQueue.main.async { self.entries = rows; self.path = "/var/mobile/Containers/Data/Application" }
        }
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
            try self.withAccess(source) {
                try fm.copyItem(at: sourceURL, to: folder.appendingPathComponent(sourceURL.lastPathComponent))
            }
            let destination = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("\(sourceURL.deletingPathExtension().lastPathComponent)-\(Int(Date().timeIntervalSince1970)).\(isApp ? "ipa" : "zip")")
            try fm.zipItem(at: staging, to: destination, shouldKeepParent: false)
            guard fm.fileExists(atPath: destination.path) else { throw VaultFailure(message: "No archive was produced.") }
            DispatchQueue.main.async { self.exported = destination }
        }
    }
}
