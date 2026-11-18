import SwiftUI
import UniformTypeIdentifiers

struct BackupHomeView: View {
    @StateObject private var store = StoreService()
    @StateObject private var signing = LocalSAPSigner.shared
    var body: some View {
        TabView {
            NavigationStack {
                List {
                    if !store.signedIn { Text("Search the App Store below. Sign in under Account to save IPA packages.").font(.footnote) }
                    Group {
                        HStack {
                            TextField("Find an App Store app", text: $store.query).onSubmit { store.search() }
                            Button("Search") { store.search() }.disabled(store.busy)
                        }
                        TextField("External version ID (optional)", text: $store.versionID).keyboardType(.numberPad)
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
                    Section {
                        NavigationLink("Decrypt on Stock iOS") { StockPreparationView(downloads: store.downloads) }
                        NavigationLink("Decrypt Installed Apps (Jailbreak)") { DecryptionView() }
                    }
                    if store.downloads.isEmpty { Text("Saved IPA files will appear here.").foregroundStyle(.secondary) }
                    ForEach(store.downloads, id: \.self) { url in
                        ShareLink(item: url) { Label(url.lastPathComponent, systemImage: "doc.zipper") }
                    }
                }.navigationTitle("Saved IPAs").refreshable { store.refreshDownloads() }
            }.tabItem { Label("IPAs", systemImage: "archivebox") }
            NavigationStack {
                Form {
                    Section("Apple Account") {
                        if store.signedIn {
                            Text("Signed in")
                            Button("Sign Out", role: .destructive) { store.signOut() }.disabled(store.busy)
                        } else {
                            TextField("Email or phone number", text: $store.email).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username).disabled(store.busy)
                            SecureField("Password", text: $store.password).textContentType(.password).disabled(store.busy)
                            if !store.verificationNotice.isEmpty { Text(store.verificationNotice).font(.footnote) }
                            if store.canRequestApproval {
                                Button("Request Approval on Other Devices") { store.requestApproval() }.disabled(store.busy)
                            }
                            if store.needsCode {
                                Button("Cancel Verification") { store.cancel() }.disabled(store.busy)
                            } else if !store.manualCodeEntry {
                                Button("Use a Verification Code") { store.showManualCodeEntry() }.disabled(store.busy)
                            } else {
                                Button("Hide Verification Code") { store.hideManualCodeEntry() }.disabled(store.busy)
                            }
                            if store.needsCode || store.manualCodeEntry {
                                TextField("Six-digit verification code", text: $store.code)
                                    .keyboardType(.numberPad).textContentType(.oneTimeCode).disabled(store.busy)
                            }
                            Button(store.code.isEmpty ? "Sign In" : "Sign In with Code") { store.signIn() }.disabled(store.busy)
                        }
                    }
                    Section {
                        Text("Signs in directly with Apple using local request signing and Store device verification. No JIT, jailbreak, root certificate or credential relay is required. Session tokens and cookies stay in the device-only Keychain. Your password is not saved.").font(.footnote)
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
                        Text("Local Apple Store authentication")
                        Link("AppVault source", destination: URL(string: "https://github.com/soum91/AppVault")!)
                        Text("On-device authentication handles SAP signing, Store device attestation and IPA authorization. Authentication components are downloaded once and verified before use. Keep AppVault open during downloads. Physical-device account login and exports remain unverified.").font(.footnote)
                    }
                }.navigationTitle("Settings")
            }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .overlay(alignment: .center) {
            if signing.isPresented, let web = signing.webView {
                // The runtime has no visual content, but WebKit must remain
                // visibly attached at a real size while its WASM signer runs.
                // A 1x1 translucent offscreen view is prone to WebContent
                // suspension/termination on iOS 16 under memory pressure.
                VStack(spacing: 12) {
                    Text("Local authentication engine").font(.headline)
                    SigningRuntimeView(web: web)
                        .frame(height: 140)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    Text(signing.stage).font(.caption).foregroundStyle(.secondary)
                    Text("Keep AppVault open during this step.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: 360)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding()
            }
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
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
