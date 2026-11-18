import Foundation
import SwiftUI
import ZIPFoundation

struct DecryptableApp: Identifiable, Sendable {
    let id: String
    let name: String
    let version: String
    let path: URL
}

@MainActor final class DecryptionService: ObservableObject {
    @Published var apps: [DecryptableApp] = []
    @Published var busy = false
    @Published var status = "Ready"
    @Published var error: String?
    @Published var output: URL?
    @Published var log = "No decryption attempted."
    let privileged = AVHasDecryptionPrivileges()
    private let worker = DispatchQueue(label: "appvault.decryption", qos: .userInitiated)
    var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "AppVault \(version) (\(build))\niOS \(UIDevice.current.systemVersion)\nPrivileged package: \(privileged)\n\(log)\nPhysical-device decryption: unverified by maintainer"
    }
    func discover() {
        guard !busy else { return }
        guard privileged else { error = "Install the AppVault rootless jailbreak DEB on your jailbroken iPhone. A normally sideloaded IPA cannot read or decrypt other installed apps."; return }
        busy = true; status = "Reading installed app bundles"
        worker.async {
            do {
                let fm = FileManager.default
                let root = URL(fileURLWithPath: "/var/containers/Bundle/Application", isDirectory: true)
                let containers = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                var apps: [DecryptableApp] = []
                for container in containers {
                    let bundles = try fm.contentsOfDirectory(at: container, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
                    for bundle in bundles {
                        guard let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Info.plist")) as? [String: Any],
                              let id = info["CFBundleIdentifier"] as? String, id != Bundle.main.bundleIdentifier else { continue }
                        apps.append(DecryptableApp(id: id, name: info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? id,
                                                  version: info["CFBundleShortVersionString"] as? String ?? "?", path: bundle))
                    }
                }
                let rows = apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                DispatchQueue.main.async { self.apps = rows; self.busy = false; self.status = "\(rows.count) installed apps" }
            } catch { DispatchQueue.main.async { self.finish(error) } }
        }
    }
    func decrypt(_ app: DecryptableApp) {
        guard privileged, !busy else { return }
        output = nil; error = nil; busy = true; status = "Copying \(app.name)"
        log = "Target: \(app.id) version \(app.version)\n"
        worker.async {
            do {
                let source = app.path.resolvingSymlinksInPath()
                guard source.path.hasPrefix("/private/var/containers/Bundle/Application/") || source.path.hasPrefix("/var/containers/Bundle/Application/") else {
                    throw VaultFailure(message: "Only installed user app bundles can be exported.")
                }
                let folder = VaultStorage.exports.appendingPathComponent("IPAs", isDirectory: true)
                try VaultStorage.ensureWritable(folder, operation: "decrypted IPA export")
                try VaultStorage.ensureWritable(VaultStorage.workspace, operation: "IPA staging")
                let out = try IPAExportEngine.export(source: source, appName: source.lastPathComponent,
                    identifier: app.id, folder: folder, workspace: VaultStorage.workspace) { message in
                    DispatchQueue.main.async { self.status = message; self.log += message + "\n" }
                }
                DispatchQueue.main.async { self.busy = false; self.output = out; self.status = "Export complete" }
            } catch { DispatchQueue.main.async { self.finish(error) } }
        }
    }

    private func finish(_ failure: Error) {
        busy = false; status = "Export failed"; error = failure.localizedDescription
        log += "FAILED: \(failure.localizedDescription)\nNo IPA published for this attempt.\n"
    }
}

struct DecryptionView: View {
    @StateObject private var service = DecryptionService()
    var body: some View {
        List {
            Section {
                Text("Export a decrypted IPA from an app installed on this jailbroken device. Your matching App Store license is required. Downloads from Apple stay encrypted until separately decrypted here.").font(.footnote)
                if service.privileged {
                    Button("Find Installed Apps") { service.discover() }.disabled(service.busy)
                } else {
                    Text("Requires the rootless jailbreak package. Install it on your Dopamine iPhone; the stock sideloaded app cannot provide these privileges.").font(.footnote)
                    Link("Download jailbreak package", destination: URL(string: "https://github.com/soum91/AppVault/releases")!)
                }
            }
            if service.busy { HStack { ProgressView(); Text(service.status).font(.footnote) } }
            if let output = service.output { Section("Verified IPA") { ShareLink(item: output) { Label(output.lastPathComponent, systemImage: "square.and.arrow.up") } } }
            Section("Installed Apps") {
                ForEach(service.apps) { app in
                    VStack(alignment: .leading) {
                        Text(app.name).font(.headline)
                        Text("\(app.id) · \(app.version)").font(.caption).foregroundStyle(.secondary)
                        Button("Decrypt and Export IPA") { service.decrypt(app) }.disabled(service.busy)
                    }
                }
            }
            Section { NavigationLink("Decryption Report") { DiscoveryReport(text: service.report) } }
        }.navigationTitle("Decrypt Installed Apps")
        .alert("Decryption Failed", isPresented: Binding(get: { service.error != nil }, set: { if !$0 { service.error = nil } })) { Button("OK") { service.error = nil } } message: { Text(service.error ?? "") }
    }
}
