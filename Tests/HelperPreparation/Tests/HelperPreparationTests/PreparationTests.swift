import XCTest
import Foundation
import ZIPFoundation
@testable import HelperPreparation

final class PreparationTests: XCTestCase {
    let fm = FileManager.default
    func fixture(replication: String = "PlugIns/Test.appex/SC_Info/Test.sinf", license: Bool = true, body: (URL, URL, URL) throws -> Void) throws {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let input = root.appendingPathComponent("input/Payload/Example.app")
        let helper = root.appendingPathComponent("template/Payload/AppVaultDecrypt.app")
        try fm.createDirectory(at: input.appendingPathComponent("SC_Info"), withIntermediateDirectories: true)
        try fm.createDirectory(at: input.appendingPathComponent("Watch/Test.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: helper, withIntermediateDirectories: true)
        func plist(_ value: [String: Any], _ path: URL) throws { try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: path) }
        try plist(["CFBundleIdentifier":"com.example.target", "CFBundleExecutable":"Example", "CFBundleName":"Example"], input.appendingPathComponent("Info.plist"))
        try Data("ciphertext fixture".utf8).write(to: input.appendingPathComponent("Example"))
        try Data("watch fixture".utf8).write(to: input.appendingPathComponent("Watch/Test.app/Binary"))
        try plist(["SinfPaths":["SC_Info/Example.sinf"], "SinfReplicationPaths":[replication]], input.appendingPathComponent("SC_Info/Manifest.plist"))
        if license { try Data("license fixture".utf8).write(to: input.appendingPathComponent("SC_Info/Example.sinf")) }
        try plist(["CFBundleIdentifier":"com.soum91.appvault.decrypthelper", "CFBundleExecutable":"AppVaultDecrypt"], helper.appendingPathComponent("Info.plist"))
        try Data("helper fixture".utf8).write(to: helper.appendingPathComponent("AppVaultDecrypt"))
        let ipa = root.appendingPathComponent("input.ipa"), template = root.appendingPathComponent("template.zip")
        try fm.zipItem(at: root.appendingPathComponent("input/Payload"), to: ipa, shouldKeepParent: true)
        try fm.zipItem(at: root.appendingPathComponent("template/Payload"), to: template, shouldKeepParent: true)
        try body(ipa, template, root)
    }
    func testPreparedHelperPreservesTargetAndReplicatesLicense() throws {
        try fixture { ipa, template, root in
            let output = try HelperPreparation.prepare(ipa: ipa, template: template, folder: root.appendingPathComponent("out")) { _ in }
            let extracted = root.appendingPathComponent("check")
            try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
            try fm.unzipItem(at: output, to: extracted)
            let helper = extracted.appendingPathComponent("Payload/AppVaultDecrypt.app")
            let source = helper.appendingPathComponent("EmbeddedPayload/Target")
            let manifest = try PropertyListDecoder().decode(HelperManifest.self, from: Data(contentsOf: helper.appendingPathComponent("AppVaultHelper.plist")))
            XCTAssertEqual(manifest.appName, "Example.app")
            XCTAssertFalse(fm.fileExists(atPath: source.appendingPathComponent("Watch").path))
            XCTAssertTrue(fm.fileExists(atPath: source.appendingPathComponent("PlugIns/Test.appex/SC_Info/Test.sinf").path))
            XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("Example")), Data("ciphertext fixture".utf8))
            try manifest.verify(source)
            try Data("signer changed encrypted binary".utf8).write(to: source.appendingPathComponent("Example"))
            XCTAssertThrowsError(try manifest.verify(source))
        }
    }
    func testTraversalInReplicationFails() throws {
        try fixture(replication: "../../outside.sinf") { ipa, template, root in
            XCTAssertThrowsError(try HelperPreparation.prepare(ipa: ipa, template: template, folder: root.appendingPathComponent("out")) { _ in })
        }
    }
    func testUnlicensedIPAFails() throws {
        try fixture(license: false) { ipa, template, root in
            XCTAssertThrowsError(try HelperPreparation.prepare(ipa: ipa, template: template, folder: root.appendingPathComponent("out")) { _ in })
        }
    }
    func testArchiveTraversalFailsBeforeExtraction() throws {
        try fixture { _, template, root in
            let bad = root.appendingPathComponent("bad.ipa")
            let archive = try Archive(url: bad, accessMode: .create)
            try archive.addEntry(with: "../outside", type: .file, uncompressedSize: 1) { _, _ in Data([42]) }
            XCTAssertThrowsError(try HelperPreparation.prepare(ipa: bad, template: template, folder: root.appendingPathComponent("out")) { _ in })
            XCTAssertFalse(fm.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("outside").path))
        }
    }
}
