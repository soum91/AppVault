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
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("decrypt-" + UUID().uuidString, isDirectory: true)
            var final: URL?
            defer { try? fm.removeItem(at: work) }
            do {
                let source = app.path.resolvingSymlinksInPath()
                guard source.path.hasPrefix("/private/var/containers/Bundle/Application/") || source.path.hasPrefix("/var/containers/Bundle/Application/") else {
                    throw VaultFailure(message: "Only installed user app bundles can be exported.")
                }
                let payload = work.appendingPathComponent("Payload", isDirectory: true)
                let destination = payload.appendingPathComponent(source.lastPathComponent, isDirectory: true)
                try fm.createDirectory(at: payload, withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: destination)
                var enumerationError: Error?
                guard let items = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in enumerationError = error; return false }) else {
                    throw VaultFailure(message: "Cannot enumerate installed bundle")
                }
                var binaries = 0, decrypted = 0
                for case let binary as URL in items {
                    let values = try binary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                    var detail = [CChar](repeating: 0, count: 512)
                    let encrypted = AVInspectMachO(binary.path, &detail, detail.count)
                    guard encrypted >= 0 else { throw VaultFailure(message: "\(binary.lastPathComponent): \(String(cString: detail))") }
                    guard encrypted > 0 else { continue }
                    let relative = String(binary.path.dropFirst(source.path.count + 1))
                    let target = destination.appendingPathComponent(relative)
                    DispatchQueue.main.async { self.status = "Decrypting \(relative)" }
                    let count = AVDecryptMachO(binary.path, target.path, &detail, detail.count)
                    guard count == encrypted else { throw VaultFailure(message: "\(relative): \(String(cString: detail))") }
                    guard AVInspectMachO(target.path, &detail, detail.count) == 0 else { throw VaultFailure(message: "Verification failed: encrypted slices remain in \(relative)") }
                    binaries += 1; decrypted += count
                    DispatchQueue.main.async { self.log += "Verified \(relative): \(count) decrypted slice(s)\n" }
                }
                if let enumerationError { throw enumerationError }
                // Re-scan every regular file, including extensions and nested frameworks.
                guard let verify = fm.enumerator(at: destination, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { throw VaultFailure(message: "Cannot verify output bundle") }
                for case let binary as URL in verify {
                    let values = try binary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                    var detail = [CChar](repeating: 0, count: 512)
                    guard AVInspectMachO(binary.path, &detail, detail.count) == 0 else { throw VaultFailure(message: "Output verification failed for \(binary.lastPathComponent)") }
                }
                let folder = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("IPAs", isDirectory: true)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                // Never overwrite an earlier export or an encrypted App Store download.
                let out = folder.appendingPathComponent("\(app.id)-decrypted-\(UUID().uuidString.prefix(8)).ipa")
                final = out
                DispatchQueue.main.async { self.status = "Packaging verified IPA" }
                try fm.zipItem(at: payload, to: out, shouldKeepParent: true, compressionMethod: .deflate)
                let archive = try Archive(url: out, accessMode: .read)
                guard archive["Payload/\(source.lastPathComponent)/Info.plist"] != nil else {
                    throw VaultFailure(message: "IPA archive verification failed")
                }
                DispatchQueue.main.async {
                    self.busy = false; self.output = out; self.status = "Export complete"
                    self.log += "Complete: \(binaries) binaries / \(decrypted) slices decrypted. All output Mach-O files passed encryption checks.\n"
                }
            } catch {
                if let final { try? fm.removeItem(at: final) }
                DispatchQueue.main.async { self.finish(error) }
            }
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
                    Link("Download jailbreak package", destination: URL(string: "https://github.com/soum91/AppVault/releases/tag/v0.5.0")!)
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
