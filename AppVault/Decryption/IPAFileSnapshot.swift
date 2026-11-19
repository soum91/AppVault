import Foundation

enum IPAFileSnapshot {
    static func copy(_ source: URL, to directory: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        let destination = directory.appendingPathComponent("Input.ipa")
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            do { try fileManager.copyItem(at: readableURL, to: destination) }
            catch { copyError = error }
        }
        if let copyError {
            let issue = copyError as NSError
            throw CopyFailure(domain: issue.domain, code: issue.code)
        }
        if let coordinationError {
            throw CopyFailure(domain: coordinationError.domain, code: coordinationError.code)
        }
        guard fileManager.isReadableFile(atPath: destination.path) else {
            throw CopyFailure(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        }
        return destination
    }

    private struct CopyFailure: LocalizedError {
        let domain: String
        let code: Int
        var errorDescription: String? {
            "AppVault could not copy the selected IPA from Files (\(domain), code \(code)). Choose a local copy under On My iPhone."
        }
    }
}
