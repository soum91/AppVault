import Foundation
import MachO

// appvault-signer: runs the pinned SAP runtime with JavaScriptCore in its own
// process. AppVault's UI process can lose its single MAP_JIT region to code
// injected into UIKit apps, which leaves JavaScriptCore without JIT and
// WebAssembly. This helper links no UIKit and talks to AppVault over
// newline-delimited JSON on stdin/stdout.
//
// argv: appvault-signer <loopback-base-url> <runtime-directory>

setvbuf(stdout, nil, _IOLBF, 0)
signal(SIGPIPE, SIG_IGN)

let outputLock = NSLock()
func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let line = String(data: data, encoding: .utf8) else { return }
    outputLock.lock(); defer { outputLock.unlock() }
    FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
}

/// Non-system images loaded into this process (shows tweak injection).
func injectedImages() -> [String] {
    (0..<_dyld_image_count()).compactMap { index in
        guard let raw = _dyld_get_image_name(index) else { return nil }
        let path = String(cString: raw)
        return path.hasPrefix("/System/") || path.hasPrefix("/usr/lib/") || path.contains("/AppVault.app/") ? nil : (path as NSString).lastPathComponent
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3, let base = URL(string: arguments[1]) else {
    emit(["type": "fatal", "error": "usage"]); exit(64)
}
RuntimeAssets.directory = URL(fileURLWithPath: arguments[2], isDirectory: true)

Task {
    do {
        let runtime = try await InProcessSAPRuntime.make(serverBase: base) { index in emit(["type": "stage", "index": index]) }
        emit(["type": "ready", "images": injectedImages()])
        // Requests arrive on stdin, one JSON object per line.
        Thread.detachNewThread {
            while let line = readLine(strippingNewline: true) {
                guard let data = line.data(using: .utf8),
                      let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = request["id"] as? Int else { continue }
                if request["type"] as? String == "shutdown" { exit(0) }
                let script = request["script"] as? String ?? ""
                let values = request["arguments"] as? [String: String] ?? [:]
                runtime.call(script: script, arguments: values) { result in
                    switch result {
                    case .success(let value): emit(["type": "result", "id": id, "ok": true, "value": value])
                    case .failure(let error): emit(["type": "result", "id": id, "ok": false, "error": error.localizedDescription])
                    }
                }
            }
            exit(0) // AppVault closed the pipe.
        }
    } catch InProcessSAPRuntime.Failure.webAssemblyUnavailable {
        emit(["type": "fatal", "error": "wasm-unavailable", "images": injectedImages()]); exit(70)
    } catch {
        emit(["type": "fatal", "error": error.localizedDescription, "images": injectedImages()]); exit(70)
    }
}
dispatchMain()
