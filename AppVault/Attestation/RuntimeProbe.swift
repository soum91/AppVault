import Foundation
import Darwin
import JavaScriptCore

@_silgen_name("csops")
private func csops(_ pid: pid_t, _ ops: UInt32, _ useraddr: UnsafeMutableRawPointer?, _ usersize: Int) -> Int32

/// Credentials-free facts about why the local signer can or cannot run.
/// Shown in Settings > Backend Report. Rootless installs are unsandboxed, so
/// they can also read the newest WebContent crash/jetsam reports.
enum RuntimeProbe {
    static func report() -> String {
        var lines = ["Signer environment:"]
        lines.append("  dynamic-codesigning entitlement (runtime): \(entitlement("dynamic-codesigning"))")
        lines.append("  platform-application entitlement (runtime): \(entitlement("platform-application"))")
        lines.append("  code-signing flags: \(codeSigningFlags())")
        lines.append("  MAP_JIT probe: \(VaultStorage.isRootless ? mapJITProbe() : "skipped (sandboxed)")")
        lines.append("  JavaScriptCore: \(javaScriptCoreProbe())")
        lines.append("  JSC env: useJIT=\(environment("JSC_useJIT")) useWebAssembly=\(environment("JSC_useWebAssembly"))")
        if VaultStorage.isRootless { lines.append(contentsOf: crashReports()) }
        return lines.joined(separator: "\n")
    }

    private static func environment(_ key: String) -> String { getenv(key).map { String(cString: $0) } ?? "unset" }

    // MARK: - Entitlements and code signing

    private typealias TaskCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias TaskCopyValue = @convention(c) (AnyObject, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<AnyObject>?

    private static func entitlement(_ key: String) -> String {
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW) else { return "unknown (Security unavailable)" }
        defer { dlclose(security) }
        guard let createSymbol = dlsym(security, "SecTaskCreateFromSelf"),
              let copySymbol = dlsym(security, "SecTaskCopyValueForEntitlement") else { return "unknown (SecTask unavailable)" }
        let create = unsafeBitCast(createSymbol, to: TaskCreate.self)
        let copy = unsafeBitCast(copySymbol, to: TaskCopyValue.self)
        guard let task = create(nil)?.takeRetainedValue() else { return "unknown (no task)" }
        guard let value = copy(task, key as CFString, nil)?.takeRetainedValue() else { return "absent" }
        if let flag = value as? Bool { return flag ? "true" : "false" }
        return "present (\(type(of: value)))"
    }

    private static func codeSigningFlags() -> String {
        var flags: UInt32 = 0
        guard csops(getpid(), 0, &flags, MemoryLayout<UInt32>.size) == 0 else { return "unavailable (errno \(errno))" }
        let names: [(UInt32, String)] = [(0x1, "VALID"), (0x4, "GET_TASK_ALLOW"), (0x100, "HARD"), (0x200, "KILL"),
                                         (0x800, "RESTRICT"), (0x2000, "ENFORCEMENT"), (0x4000000, "PLATFORM_BINARY"),
                                         (0x10000000, "DEBUGGED")]
        let set = names.filter { flags & $0.0 != 0 }.map(\.1)
        return String(format: "0x%08x", flags) + " [" + set.joined(separator: ",") + "]"
    }

    private static func mapJITProbe() -> String {
        let size = Int(getpagesize())
        errno = 0
        let pointer = mmap(nil, size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | 0x0800 /* MAP_JIT */, -1, 0)
        if pointer == nil || pointer == UnsafeMutableRawPointer(bitPattern: -1) {
            let code = errno
            // iOS allows one MAP_JIT region per process; EINVAL usually means
            // JavaScriptCore already holds it.
            return code == EINVAL ? "EINVAL (a JIT region likely already exists, e.g. JavaScriptCore's)" : "failed (errno \(code))"
        }
        munmap(pointer, size)
        return "ok"
    }

    private static func javaScriptCoreProbe() -> String {
        guard let context = JSContext() else { return "no context" }
        let script = """
        (() => {
          if (typeof WebAssembly !== 'object') return 'WebAssembly=' + typeof WebAssembly;
          try { new WebAssembly.Module(new Uint8Array([0,97,115,109,1,0,0,0])); return 'WebAssembly=object; module=ok'; }
          catch (e) { return 'WebAssembly=object; module=' + (e && e.name); }
        })()
        """
        return context.evaluateScript(script)?.toString() ?? "evaluation failed"
    }

    // MARK: - WebContent crash and jetsam reports (rootless only)

    private static let crashFolder = URL(fileURLWithPath: "/var/mobile/Library/Logs/CrashReporter", isDirectory: true)

    private static func crashReports() -> [String] {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: crashFolder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return ["WebContent reports: folder unreadable"]
        }
        let cutoff = Date().addingTimeInterval(-6 * 3600)
        func modified(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        let recent = files.filter { $0.pathExtension == "ips" && modified($0) > cutoff }.sorted { modified($0) > modified($1) }
        let web = recent.filter { $0.lastPathComponent.contains("WebContent") || $0.lastPathComponent.contains("WebKit") }
        let jetsam = recent.filter { $0.lastPathComponent.hasPrefix("JetsamEvent") }
        var lines = ["WebContent reports (last 6 h): \(web.count) crash, \(jetsam.count) jetsam"]
        for url in web.prefix(2) { lines.append(contentsOf: summarizeCrash(url)) }
        for url in jetsam.prefix(3) {
            if let line = summarizeJetsam(url) { lines.append(line); break }
        }
        return lines
    }

    private static func reportJSON(_ url: URL) -> (header: [String: Any], body: [String: Any])? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4 << 20),
              let newline = data.firstIndex(of: 0x0A) else { return nil }
        let header = (try? JSONSerialization.jsonObject(with: data[..<newline])) as? [String: Any] ?? [:]
        let body = (try? JSONSerialization.jsonObject(with: data[data.index(after: newline)...])) as? [String: Any] ?? [:]
        return (header, body)
    }

    private static func clip(_ value: Any?, _ limit: Int = 160) -> String {
        guard let value else { return "-" }
        let text = String(describing: value).replacingOccurrences(of: "\n", with: " ")
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    private static func summarizeCrash(_ url: URL) -> [String] {
        guard let (header, body) = reportJSON(url) else { return ["  \(url.lastPathComponent): unreadable"] }
        var lines = ["  \(url.lastPathComponent) (bug_type \(clip(header["bug_type"])), \(clip(header["timestamp"])))"]
        let exception = body["exception"] as? [String: Any]
        lines.append("    exception: \(clip(exception?["type"])) \(clip(exception?["signal"])) \(clip(exception?["subtype"]))")
        if let termination = body["termination"] as? [String: Any] {
            lines.append("    termination: \(clip(termination["namespace"])) code \(clip(termination["code"])) \(clip(termination["indicator"]))")
            if let reasons = termination["reasons"] as? [Any] { lines.append("    reasons: \(clip(reasons.prefix(3).map { "\($0)" }.joined(separator: " | "), 300))") }
        }
        if let asi = body["asi"] as? [String: Any] { lines.append("    asi: \(clip(asi, 300))") }
        if let faulting = body["faultingThread"] as? Int,
           let threads = body["threads"] as? [[String: Any]], faulting < threads.count,
           let frames = threads[faulting]["frames"] as? [[String: Any]] {
            let images = (body["usedImages"] as? [[String: Any]]) ?? []
            let top = frames.prefix(8).map { frame -> String in
                let index = frame["imageIndex"] as? Int ?? -1
                let image = index >= 0 && index < images.count ? (images[index]["name"] as? String ?? "?") : "?"
                return image + ":" + (frame["symbol"] as? String ?? clip(frame["imageOffset"], 20))
            }
            lines.append("    frames: \(top.joined(separator: " < "))")
        }
        return lines
    }

    private static func summarizeJetsam(_ url: URL) -> String? {
        guard let (_, body) = reportJSON(url), let processes = body["processes"] as? [[String: Any]] else { return nil }
        guard let hit = processes.first(where: { ($0["name"] as? String)?.contains("WebContent") == true && $0["reason"] != nil }) else { return nil }
        return "  \(url.lastPathComponent): WebContent jetsam reason \(clip(hit["reason"])), rpages \(clip(hit["rpages"]))"
    }
}
