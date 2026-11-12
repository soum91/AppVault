import SwiftUI
import UniformTypeIdentifiers

struct BackupHomeView: View {
    @StateObject private var service = BackupService()
    @State private var showImporter = false
    @State private var exportURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AppVault", systemImage: "archivebox.fill").font(.largeTitle.bold())
                        Text("Create portable backups of selected IPA files or readable app data.")
                            .foregroundStyle(.secondary)
                        Text(service.status).font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section("Backup") {
                    Button { showImporter = true } label: {
                        Label("Import IPA from Files", systemImage: "square.and.arrow.down")
                    }
                    Button { service.scan() } label: {
                        Label("Scan accessible app containers", systemImage: "magnifyingglass")
                    }.disabled(service.isWorking)
                }
                if !service.items.isEmpty {
                    Section("App Data") {
                        ForEach(service.items) { item in
                            Button { makeBackup(item) } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(item.displayName).foregroundStyle(.primary)
                                        Text(item.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.down.doc")
                                }
                            }
                        }
                    }
                }
                Section("About backups") {
                    Text("IPA backups contain the selected installation package. App data backups contain the readable container and a manifest; they do not include signing credentials or guarantee that an app can be reinstalled.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Backup")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        guard url.pathExtension.lowercased() == "ipa" else {
                            errorMessage = "Select an .ipa file."
                            return
                        }
                        makeIPABackup(url)
                    }
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                if let exportURL { ShareSheet(activityItems: [exportURL]) }
            }
            .alert("Backup failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Unknown error") }
        }
    }

    private func makeIPABackup(_ url: URL) {
        do { exportURL = try service.importIPA(from: url) } catch { errorMessage = error.localizedDescription }
    }
    private func makeBackup(_ item: BackupItem) {
        do { exportURL = try service.backup(item) } catch { errorMessage = error.localizedDescription }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
