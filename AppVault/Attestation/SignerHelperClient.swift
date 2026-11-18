import Foundation

/// What LocalSAPSigner needs from a JavaScriptCore signer host: the in-process
/// runtime, or the out-of-process `appvault-signer` helper.
protocol SAPRuntimeHost: AnyObject, Sendable {
    var isAlive: Bool { get }
    func call(script: String, arguments: [String: String], completion: @escaping @Sendable (Result<String, Error>) -> Void)
    func shutdown()
}

extension InProcessSAPRuntime: SAPRuntimeHost {}

/// Runs the SAP runtime in `AppVault.app/appvault-signer` (rootless DEB only).
///
/// On Dopamine/iOS 16.1.1, AppVault's UI process already had its single
/// MAP_JIT region taken when JavaScriptCore initialized (MAP_JIT EINVAL), so
/// JavaScriptCore disabled JIT and WebAssembly. The helper links no UIKit, so
/// UIKit tweak injection does not load into it, and its JavaScriptCore can
/// reserve the JIT region.
final class SignerHelperClient: SAPRuntimeHost, @unchecked Sendable {
    enum Failure: Error {
        case missing
        case wasmUnavailable(images: [String])
        case failed(String)
    }

    static var executable: URL { Bundle.main.bundleURL.appendingPathComponent("appvault-signer") }
    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }

    private let lock = NSLock()
    private let pid: pid_t
    private let writer: FileHandle
    private let reader: FileHandle
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: @Sendable (Result<String, Error>) -> Void] = [:]
    private var startup: CheckedContinuation<[String], Error>?
    private var alive = true
    private let onStage: @Sendable (Int) -> Void
    /// Non-system images loaded in the helper, from its handshake.
    private(set) var injectedImages: [String] = []

    private init(pid: pid_t, writeFD: Int32, readFD: Int32, onStage: @escaping @Sendable (Int) -> Void) {
        self.pid = pid
        writer = FileHandle(fileDescriptor: writeFD, closeOnDealloc: true)
        reader = FileHandle(fileDescriptor: readFD, closeOnDealloc: true)
        self.onStage = onStage
    }

    static func make(serverBase: URL, runtimeDirectory: URL, onStage: @escaping @Sendable (Int) -> Void) async throws -> SignerHelperClient {
        guard isInstalled else { throw Failure.missing }
        var writeFD: Int32 = -1, readFD: Int32 = -1
        let pid = AVSpawnSigner(executable.path, [serverBase.absoluteString, runtimeDirectory.path], &writeFD, &readFD)
        guard pid > 0 else { throw Failure.failed("spawn failed (errno \(-pid))") }
        let client = SignerHelperClient(pid: pid, writeFD: writeFD, readFD: readFD, onStage: onStage)
        do {
            client.injectedImages = try await withCheckedThrowingContinuation { continuation in
                client.lock.lock(); client.startup = continuation; client.lock.unlock()
                client.reader.readabilityHandler = { [weak client] handle in client?.receive(handle.availableData) }
            }
            return client
        } catch {
            client.shutdown()
            throw error
        }
    }

    var isAlive: Bool { lock.lock(); defer { lock.unlock() }; return alive }

    func call(script: String, arguments: [String: String], completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        lock.lock()
        guard alive else { lock.unlock(); completion(.failure(Failure.failed("signer helper is not running"))); return }
        nextID += 1
        let id = nextID
        pending[id] = completion
        lock.unlock()
        let request: [String: Any] = ["type": "call", "id": id, "script": script, "arguments": arguments]
        guard let data = try? JSONSerialization.data(withJSONObject: request) else {
            finish(id, .failure(Failure.failed("request encoding failed"))); return
        }
        do { try writer.write(contentsOf: data + Data([0x0A])) }
        catch { terminate(Failure.failed("signer helper pipe closed")) }
    }

    func shutdown() { terminate(CancellationError()) }

    // MARK: - Output handling

    private func receive(_ chunk: Data) {
        if chunk.isEmpty { terminate(Failure.failed("signer helper exited")); return }
        lock.lock()
        buffer.append(chunk)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        lock.unlock()
        for line in lines {
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            handle(message)
        }
    }

    private func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "ready":
            resolveStartup(.success(message["images"] as? [String] ?? []))
        case "fatal":
            let images = message["images"] as? [String] ?? []
            let error = message["error"] as? String ?? "unknown"
            injectedImages = images
            terminate(error == "wasm-unavailable" ? Failure.wasmUnavailable(images: images) : Failure.failed(error))
        case "stage":
            if let index = message["index"] as? Int { onStage(index) }
        case "result":
            guard let id = message["id"] as? Int else { return }
            if message["ok"] as? Bool == true, let value = message["value"] as? String { finish(id, .success(value)) }
            else { finish(id, .failure(ToolError.message(message["error"] as? String ?? "Local signer helper failed."))) }
        default:
            break
        }
    }

    private func resolveStartup(_ result: Result<[String], Error>) {
        lock.lock(); let continuation = startup; startup = nil; lock.unlock()
        switch result {
        case .success(let images): continuation?.resume(returning: images)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    private func finish(_ id: Int, _ result: Result<String, Error>) {
        lock.lock(); let completion = pending.removeValue(forKey: id); lock.unlock()
        completion?(result)
    }

    private func terminate(_ error: Error) {
        lock.lock()
        guard alive else { lock.unlock(); return }
        alive = false
        let waiting = pending
        pending.removeAll()
        lock.unlock()
        reader.readabilityHandler = nil
        resolveStartup(.failure(error))
        waiting.values.forEach { $0(.failure(error)) }
        let target = pid
        DispatchQueue.global(qos: .utility).async { AVStopSigner(target) }
    }
}
