import SwiftUI

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
                        Text("Open an app's bundle or data folder, then export a backup.").font(.footnote).foregroundStyle(.secondary)
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
                        Button("Application Bundles") { open("/var/containers/Bundle/Application") }
                        Button("Application Data") { open("/var/mobile/Containers/Data/Application") }
                        Button("Shared App Groups") { open("/var/mobile/Containers/Shared/AppGroup") }
                        Button("Discover Data Folders") { tab = 1; service.discoverData() }
                        Text("Discovery can take several minutes. App Groups must be retained during signing. Access errors report the actual result from worse_query.").font(.footnote)
                    }
                    Section("IPA Backups") {
                        Text("Exporting a readable .app folder creates Payload/App.app inside an IPA. App Store executables may remain encrypted. A sandbox extension does not decrypt them or guarantee access to the Bundle directory.").font(.footnote)
                    }
                    Section("Version") { Text("AppVault 0.2.1 (4)") }
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
