import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor final class StockPreparationService: ObservableObject {
    @Published var busy = false
    @Published var status = "Choose an account-authorized IPA"
    @Published var output: URL?
    @Published var error: String?
    @Published var log = "No helper prepared."
    var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "AppVault \(version) (\(build))\niOS \(UIDevice.current.systemVersion)\nStock helper preparation\n\(log)\nPhysical-device helper signing/decryption: unverified"
    }
    func prepare(_ input: URL, fromFiles: Bool = false) {
        guard !busy else { return }
        guard let template = Bundle.main.url(forResource: "DecryptHelper", withExtension: "zip") else { error = "This build has no helper template. Install the complete AppVault release."; return }
        output = nil; error = nil; busy = true; status = "Preparing IPA"; log = "Preparing local helper. No credentials or packages are uploaded.\n"
        let folder = VaultStorage.exports.appendingPathComponent("Helpers", isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            var importedDirectory: URL?
            defer {
                if let importedDirectory { try? FileManager.default.removeItem(at: importedDirectory) }
            }
            do {
                try VaultStorage.ensureWritable(folder, operation: "stock helper IPA export")
                try VaultStorage.ensureWritable(VaultStorage.workspace, operation: "stock helper staging")
                let localInput: URL
                if fromFiles {
                    DispatchQueue.main.async {
                        self.status = "Copying IPA from Files"
                        self.log += "Copying IPA from Files\n"
                    }
                    let directory = VaultStorage.workspace.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    importedDirectory = directory
                    localInput = try IPAFileSnapshot.copy(input, to: directory)
                } else {
                    localInput = input
                }
                let out = try HelperPreparation.prepare(ipa: localInput, template: template,
                                                       folder: folder, workspace: VaultStorage.workspace) { message in
                    DispatchQueue.main.async { self.status = message; self.log += message + "\n" }
                }
                DispatchQueue.main.async { self.output = out; self.busy = false; self.status = "Ready to sign and install" }
            } catch {
                DispatchQueue.main.async { self.busy = false; self.error = error.localizedDescription; self.status = "Preparation failed"; self.log += "FAILED: \(error.localizedDescription)\n" }
            }
        }
    }
}
struct StockPreparationView: View {
    let downloads: [URL]
    @StateObject private var service = StockPreparationService()
    @State private var importing = false
    var body: some View {
        List {
            Section("How it works") {
                Text("1. Prepare a helper from an encrypted IPA that includes your App Store license.\n2. Sign and install the helper using payload-preserving EmberSign.\n3. Open the installed helper and tap Decrypt and Export.\n4. Share the verified decrypted IPA.").font(.footnote)
                Text("The iPhone must be signed in to the Apple Account that owns the app. Use development signing and Developer Mode. Each target needs a new helper installation; the same helper identifier is reused.").font(.footnote)
                Text("The target must be inside the installed helper bundle: FairPlay cannot read its license from AppVault's Downloads folder. Simply importing an IPA does not decrypt it.").font(.footnote)
                Text("Device signing and decryption remain unverified. A signer that modifies the embedded payload will be rejected by the helper's integrity check.").font(.footnote)
                Link("Compatible signing instructions", destination: URL(string: "https://github.com/soum91/AppVault/blob/main/STOCK_DECRYPTION.md")!)
            }
            Section("Choose IPA") {
                Button("Import IPA from Files") { importing = true }.disabled(service.busy)
                ForEach(downloads, id: \.self) { input in
                    Button { service.prepare(input) } label: { Label(input.lastPathComponent, systemImage: "doc.zipper") }.disabled(service.busy)
                }
            }
            if service.busy { HStack { ProgressView(); Text(service.status).font(.footnote) } }
            if let output = service.output {
                Section("Helper ready") {
                    Text("This IPA is a signing helper containing encrypted resources. It is not the decrypted output.").font(.footnote)
                    ShareLink(item: output) { Label("Share Helper to Signer or Files", systemImage: "square.and.arrow.up") }
                }
            }
            Section { NavigationLink("Preparation Report") { DiscoveryReport(text: service.report) } }
        }.navigationTitle("Decrypt on Stock iOS")
        .sheet(isPresented: $importing) {
            IPADocumentPicker { url in
                importing = false
                if let url { service.prepare(url, fromFiles: true) }
            }
        }
        .alert("Helper Preparation", isPresented: Binding(get: { service.error != nil }, set: { if !$0 { service.error = nil } })) { Button("OK") { service.error = nil } } message: { Text(service.error ?? "") }
    }
}


// Ask Files for an imported copy. The helper builder only reads its own
// local snapshot and never reopens a document-provider URL.
private struct IPADocumentPicker: UIViewControllerRepresentable {
    let completed: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType(filenameExtension: "ipa") ?? .zip, .zip],
            asCopy: true
        )
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Delegate { Delegate(completed: completed) }

    final class Delegate: NSObject, UIDocumentPickerDelegate {
        let completed: (URL?) -> Void
        init(completed: @escaping (URL?) -> Void) { self.completed = completed }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completed(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completed(nil)
        }
    }
}
