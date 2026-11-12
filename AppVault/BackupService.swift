import Foundation
import UniformTypeIdentifiers
import Combine
import UIKit
import Darwin

/// Container access is isolated behind this service. A normal build only
/// backs up IPA files selected by the user. The optional worse_query path
/// requires a separately configured bridge and matching entitlements.
final class BackupService: ObservableObject {
    @Published private(set) var items: [BackupItem] = []
    @Published private(set) var status = "Choose an IPA or scan accessible app containers."
    @Published private(set) var isWorking = false

    #if WORSE_QUERY_ENABLED
    private let appGroup = "group.cc.forcequit.worse-query"
    #endif

    func scan() {
        isWorking = true
        defer { isWorking = false }
        #if WORSE_QUERY_ENABLED
        items = scanAccessibleContainers()
        status = items.isEmpty ? "No readable containers found." : "Found \(items.count) app containers."
        #else
        items = []
        status = "Container scanning needs a configured worse_query bridge and matching App Group entitlement. Use Import IPA to back up a selected IPA."
        #endif
    }

    func importIPA(from source: URL) throws -> URL {
        let hasScope = source.startAccessingSecurityScopedResource()
        defer { if hasScope { source.stopAccessingSecurityScopedResource() } }
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let ipaDir = base.appendingPathComponent("IPA", isDirectory: true)
        try FileManager.default.createDirectory(at: ipaDir, withIntermediateDirectories: true)
        let target = ipaDir.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: target)
        let manifest = BackupManifest(formatVersion: 1, createdAt: Date(),
            deviceName: UIDevice.current.name, systemVersion: UIDevice.current.systemVersion,
            bundleIdentifier: "", displayName: source.deletingPathExtension().lastPathComponent,
            included: ["IPA/\(source.lastPathComponent)"])
        try writeManifest(manifest, to: base)
        return try archive(base)
    }

    func backup(_ item: BackupItem) throws -> URL {
        #if WORSE_QUERY_ENABLED
        guard let root = openContainer(item.containerPath) else { throw BackupError.accessUnavailable }
        defer { releaseContainerAccess() }
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let data = base.appendingPathComponent("Data", isDirectory: true)
        try FileManager.default.copyItem(at: root, to: data)
        let manifest = BackupManifest(formatVersion: 1, createdAt: Date(),
            deviceName: UIDevice.current.name, systemVersion: UIDevice.current.systemVersion,
            bundleIdentifier: item.bundleIdentifier, displayName: item.displayName,
            included: ["Data/"])
        try writeManifest(manifest, to: base)
        return try archive(base)
        #else
        throw BackupError.accessUnavailable
        #endif
    }

    private func writeManifest(_ manifest: BackupManifest, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func archive(_ directory: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(directory.lastPathComponent + ".zip")
        try? FileManager.default.removeItem(at: destination)
        var coordinatorError: NSError?
        var operationError: Error?
        NSFileCoordinator().coordinate(readingItemAt: directory, options: .forUploading, error: &coordinatorError) { zippedURL in
            do { try FileManager.default.copyItem(at: zippedURL, to: destination) }
            catch { operationError = error }
        }
        if let error = operationError ?? coordinatorError { throw error }
        guard FileManager.default.fileExists(atPath: destination.path) else { throw BackupError.destinationUnavailable }
        try? FileManager.default.removeItem(at: directory)
        return destination
    }

    #if WORSE_QUERY_ENABLED
    private func scanAccessibleContainers() -> [BackupItem] {
        let appData = "/var/mobile/Containers/Data/Application"
        guard openContainer(appData) else { return [] }
        defer { releaseContainerAccess() }
        let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: appData),
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true else { return nil }
            var idBuffer = [CChar](repeating: 0, count: 512)
            let idLength = url.path.withCString { getxattr($0, "com.apple.containermanager.identifier", &idBuffer, idBuffer.count - 1, 0, 0) }
            let bundleID = idLength > 0 ? String(cString: idBuffer) : url.lastPathComponent
            return BackupItem(bundleIdentifier: bundleID, containerPath: url.path, displayName: bundleID, dataSize: 0)
        }
    }

    private func openContainer(_ path: String) -> Bool {
        path.withCString { appvault_worse_query($0, appGroup, false, false) >= 0 }
    }
    private func releaseContainerAccess() { appvault_worse_query_release() }
    #endif
}
