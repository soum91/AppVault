import SwiftUI
import UniformTypeIdentifiers

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
