import SwiftUI
import UniformTypeIdentifiers

struct BackupHomeView: View {
    @StateObject private var store = IPAToolService()
    var body: some View {
        TabView {
            NavigationStack {
                List {
                    if !store.capable { capability }
                    if !store.signedIn {
                        Text("Sign in under Account to search and save App Store IPA packages.")
                    } else {
                        HStack {
                            TextField("Find an App Store app", text: $store.query).onSubmit { store.search() }
                            Button("Search") { store.search() }.disabled(store.busy)
                        }
                        ForEach(store.apps) { app in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(app.trackName ?? app.bundleId ?? "App").font(.headline)
                                Text("\(app.bundleId ?? "") · \(app.version ?? "")").font(.caption).foregroundStyle(.secondary)
                                Button { store.download(app) } label: { Label("Save IPA", systemImage: "arrow.down.doc") }.disabled(store.busy)
                            }.padding(.vertical, 5)
                        }
                    }
                }.navigationTitle("AppVault")
            }.tabItem { Label("Search", systemImage: "magnifyingglass") }
            NavigationStack {
                List {
                    if store.downloads.isEmpty { Text("Saved IPA files will appear here.").foregroundStyle(.secondary) }
                    ForEach(store.downloads, id: \.self) { url in
                        ShareLink(item: url) { Label(url.lastPathComponent, systemImage: "doc.zipper") }
                    }
                }.navigationTitle("Saved IPAs").refreshable { store.refreshDownloads() }
            }.tabItem { Label("IPAs", systemImage: "archivebox") }
            NavigationStack {
                Form {
                    capability
                    Section("Apple Account") {
                        if store.signedIn {
                            Text("Signed in")
                            Button("Sign Out", role: .destructive) { store.signOut() }.disabled(store.busy)
                        } else {
                            TextField("Email or phone number", text: $store.email).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username).disabled(!store.capable || store.busy)
                            SecureField("Password", text: $store.password).textContentType(.password).disabled(!store.capable || store.busy)
                            if store.needsCode { TextField("Verification code", text: $store.code).keyboardType(.numberPad).textContentType(.oneTimeCode) }
                            Button("Sign In") { store.signIn() }.disabled(store.busy || !store.capable)
                        }
                    }
                    Section {
                        Text("Uses the open-source ipatool backend directly inside AppVault. Session tokens and provisioning state are stored in this app's Keychain. Your password is not saved after sign-in. No extra root certificate is required.").font(.footnote)
                        Text("Downloads account-authorized packages from Apple. Apple DRM remains; saving an IPA does not guarantee it can be installed through a sideloader.").font(.footnote)
                    }
                }.navigationTitle("Account")
            }.tabItem { Label("Account", systemImage: "person.crop.circle") }
            NavigationStack {
                Form {
                    Section("Installed Version") {
                        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
                        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
                        Text("AppVault \(version) (\(build))").textSelection(.enabled)
                    }
                    Section("Diagnostics") { NavigationLink("Backend Report") { DiscoveryReport(text: store.report) } }
                    Section("Backend") {
                        Text("ipatool · b352566155a6").textSelection(.enabled)
                        Link("Source and license", destination: URL(string: "https://github.com/majd/ipatool")!)
                        Text("Experimental iOS integration. Login and IPA downloads have not been verified on a physical device. Keep AppVault open while downloading. The initial authentication runtime download can take time.").font(.footnote)
                    }
                }.navigationTitle("Settings")
            }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .safeAreaInset(edge: .bottom) {
            if store.busy {
                HStack { ProgressView(); Text(store.status).font(.footnote); Spacer(); Button("Cancel") { store.cancel() } }.padding().background(.regularMaterial)
            }
        }
        .alert("AppVault", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .sheet(isPresented: Binding(get: { store.exported != nil }, set: { if !$0 { store.exported = nil } })) {
            if let url = store.exported { ShareSheet(url: url) }
        }
    }
    private var capability: some View {
        Section("ipatool Runtime") {
            Label(store.capable ? "Executable memory available" : "JIT required", systemImage: store.capable ? "checkmark.circle" : "exclamationmark.triangle")
            if !store.capable {
                Text("iOS denied the executable memory needed by ipatool. Enable JIT for AppVault or use a compatible jailbreak. worse_query alone does not enable JIT.").font(.footnote)
            }
            Button("Check Again") { store.refreshCapability() }
        }
    }
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
struct DiscoveryReport: View {
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
        }.navigationTitle("Backend Report")
        .fileExporter(isPresented: $saving, document: ReportDocument(text: text), contentType: .plainText, defaultFilename: "AppVault-discovery") {
            switch $0 { case .success: feedback = "Report saved."; case .failure(let error): feedback = error.localizedDescription }
        }
    }
}
