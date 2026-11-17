import SwiftUI

@MainActor final class EmbeddedDecryption: ObservableObject {
    @Published var busy = false
    @Published var status = "Ready"
    @Published var error: String?
    @Published var output: URL?
    @Published var log = "No embedded export attempted."
    let manifest: HelperManifest?
    private let source: URL
    init() {
        source = Bundle.main.bundleURL.appendingPathComponent("EmbeddedPayload/Target")
        manifest = (try? Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("AppVaultHelper.plist"))).flatMap { try? PropertyListDecoder().decode(HelperManifest.self, from: $0) }
    }
    var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "AppVault helper \(version) (\(build))\niOS \(UIDevice.current.systemVersion)\nTarget: \(manifest?.bundleID ?? "none")\n\(log)\nPhysical-device export and diagnostics: unverified by maintainer"
    }
    func decrypt() {
        guard !busy, let manifest else { return }
        busy = true; error = nil; output = nil; status = "Checking embedded resources"
        let source = source
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Decrypted")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try manifest.verify(source)
                let out = try IPAExportEngine.export(source: source, appName: manifest.appName, identifier: manifest.bundleID, folder: folder) { message in
                    DispatchQueue.main.async { self.status = message; self.log += message + "\n" }
                }
                DispatchQueue.main.async { self.output = out; self.busy = false; self.status = "Export complete" }
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription; self.busy = false; self.status = "Export failed"; self.log += "FAILED: \(error.localizedDescription)\nNo complete IPA published.\n" }
            }
        }
    }
}
@main struct AppVaultDecryptApp: App {
    var body: some Scene { WindowGroup { HelperHome() } }
}
struct HelperHome: View {
    @StateObject private var model = EmbeddedDecryption()
    var body: some View {
        NavigationStack {
            Form {
                Section("Embedded App") {
                    if let target = model.manifest {
                        Text(target.displayName).font(.headline)
                        Text(target.bundleID).font(.caption).textSelection(.enabled)
                        Button("Decrypt and Export IPA") { model.decrypt() }.disabled(model.busy)
                    } else { Text("This is an empty helper template. Prepare a target-specific helper in AppVault first.") }
                }
                Section {
                    Text("Uses the device's FairPlay service and the embedded App Store license. The iPhone must be signed in to the account that owns the app. Keep this helper open until export finishes.").font(.footnote)
                    Text("Device decryption is not yet verified by the maintainer. Failed page reads or changed resources stop export.").font(.footnote)
                }
                if model.busy { HStack { ProgressView(); Text(model.status).font(.footnote) } }
                if let output = model.output { Section("Decrypted IPA") { ShareLink(item: output) { Label("Share Decrypted IPA", systemImage: "square.and.arrow.up") } } }
                Section { NavigationLink("Export Report") { DiscoveryReport(text: model.report) } }
                Section("Installed Version") {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
                    Text("AppVault \(version) (\(build))").textSelection(.enabled)
                }
            }.navigationTitle("AppVault Decrypt")
            .alert("Decryption Failed", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        }
    }
}
