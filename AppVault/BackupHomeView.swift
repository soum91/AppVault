import SwiftUI
import UniformTypeIdentifiers

struct BackupHomeView: View {
    @StateObject private var service = BackupService()
    @State private var tab = 0
    @State private var destination = "/var/mobile/Containers/Data/Application"
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                List {
                    Section {
                        Button { service.loadApps() } label: { Label("Find Installed Apps", systemImage: "arrow.clockwise") }
                        Text("Discover app data containers, open a folder, then export its ZIP backup.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(service.apps) { app in
                        Section(app.name) {
                            Text(app.bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if let path = app.bundlePath {
                                Button("Browse App Bundle") { open(path) }
                            }
                            if let path = app.dataPath {
                                Button("Browse App Data") { open(path) }
                            }
                        }
                    }
                }
                .navigationTitle("Applications")
            }.tabItem { Label("Apps", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack {
                List {
                    Section {
                        HStack {
                            TextField("Folder path", text: $destination).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Go") { service.browse(destination) }
                        }
                        Text(service.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack {
                            Button { open(URL(fileURLWithPath: service.path).deletingLastPathComponent().path) } label: { Label("Up", systemImage: "arrow.up") }
                            Spacer()
                            Button { service.backup(service.path) } label: { Label("Back Up Folder", systemImage: "archivebox") }
                        }
                    }
                    Section("Folders and Files") {
                        ForEach(service.entries) { entry in
                            HStack {
                                Button { if entry.directory { open(entry.path) } } label: {
                                    Label(entry.name, systemImage: entry.directory ? "folder" : "doc").lineLimit(2)
                                }.buttonStyle(.plain)
                                Spacer()
                                Button { service.backup(entry.path) } label: { Image(systemName: "square.and.arrow.up") }
                            }.padding(.vertical, 4)
                        }
                    }
                }
                .navigationTitle("Browse")
            }.tabItem { Label("Browse", systemImage: "folder") }.tag(1)
            NavigationStack {
                Form {
                    Section("Access") {
                        TextField("App Group", text: $service.group).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Application Data") { open("/var/mobile/Containers/Data/Application") }
                        Button("Shared App Groups") { open("/var/mobile/Containers/Shared/AppGroup") }
                        Button("Discover Data Folders") { tab = 1; service.discoverData() }
                        Text("Database discovery stops after 20 seconds. Refresh resumes the search. A usable App Group is required.").font(.footnote)
                    }
                    Section("IPA Backups") {
                        Text("On iOS 27.0.1, worse_query does not provide access to installed app bundles. This build can attempt app-data ZIP backups; it cannot extract installed IPAs on that OS.").font(.footnote)
                    }
                    Section("Diagnostics") { NavigationLink("Discovery Report") { DiscoveryReport(text: service.report) } }
                    Section("Installed Version") {
                        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
                        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
                        Text("AppVault \(version) (\(build))").textSelection(.enabled)
                    }
                }.navigationTitle("Settings")
            }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .disabled(service.busy)
        .safeAreaInset(edge: .bottom) {
            if service.busy {
                HStack { ProgressView(); Text(service.status).font(.footnote); Button("Cancel Scan") { service.cancelDiscovery() } }.padding().frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .alert("Access or Backup Error", isPresented: Binding(get: { service.error != nil }, set: { if !$0 { service.error = nil } })) {
            Button("OK") { service.error = nil }
        } message: { Text(service.error ?? "") }
        .sheet(isPresented: Binding(get: { service.exported != nil }, set: { if !$0 { service.exported = nil } })) {
            if let url = service.exported { ShareSheet(url: url) }
        }
        .onAppear { if service.apps.isEmpty { service.loadApps() } }
    }
    private func open(_ path: String) { destination = path; tab = 1; service.browse(path) }
}
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct ReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
private struct DiscoveryReport: View {
    let text: String
    @State private var saving = false
    @State private var feedback = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button("Copy") {
                        UIPasteboard.general.string = text
                        feedback = UIPasteboard.general.string == text ? "Copied and verified." : "Copy failed. Use Share or Save."
                    }
                    ShareLink(item: text) { Text("Share") }
                    Button("Save") { saving = true }
                }
                Text(feedback).font(.footnote)
                Text(text).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            }.padding()
        }.navigationTitle("Discovery Report")
        .fileExporter(isPresented: $saving, document: ReportDocument(text: text), contentType: .plainText, defaultFilename: "AppVault-discovery") {
            switch $0 { case .success: feedback = "Report saved."; case .failure(let error): feedback = error.localizedDescription }
        }
    }
}
