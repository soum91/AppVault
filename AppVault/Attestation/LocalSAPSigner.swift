// Adapted from mengangs/ipadn, pinned 81dd1f747e71b31629979e2c1de0fe234fe7de39. GPL-2.0-or-later.
import Foundation
import WebKit
import Combine
import CryptoKit
import UIKit

@MainActor
final class LocalSAPSigner: NSObject, ObservableObject {
    static let shared = LocalSAPSigner()
    @Published private(set) var isPresented = false
    @Published private(set) var webView: WKWebView?
    @Published private(set) var title = AppText.text("正在验证请求")
    @Published private(set) var stage = AppText.text("准备本地环境")
    @Published private(set) var stageIndex = 0
    @Published private(set) var startedAt = Date()
    let server = LoopbackServer()
    private var operationID: UUID?
    private var navigation: CheckedContinuation<Void, Error>?
    private var evaluation: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?
    private var terminalError: Error?
    private var signatureCache: [String: String] = [:]
    private var kbCache: [String: String] = [:]
    private var storeProofRecords: [String: StoreProofRecord]?
    private var cacheRevision = UUID()
    private var reusableWebView: WKWebView?
    private var reusableBase: URL?
    private var idleTimeout: Task<Void, Never>?
    private var memoryObserver: AnyCancellable?
    private var recentEvents: [String] = []
    private var lastWebContentExit = false
    /// In-process JavaScriptCore runtime used by the rootless DEB (see
    /// InProcessSAPRuntime). Kept warm like the reusable WebKit view.
    private var inProcessRuntime: InProcessSAPRuntime?
    private var inProcessBase: URL?
    /// Set when JavaScriptCore has no JIT/WebAssembly in this install, so the
    /// WebKit runtime is used instead.
    private var inProcessUnavailable = false
    /// The rootless DEB carries dynamic-codesigning and uses JavaScriptCore,
    /// because WebContent exits at spawn for that platform-signed app. The
    /// sideloaded IPA uses WebKit. WebKit stays as the rootless fallback if
    /// JavaScriptCore reports no WebAssembly.
    var usesInProcessRuntime: Bool { VaultStorage.isRootless && !inProcessUnavailable }
    var runtimeDescription: String {
        if inProcessUnavailable && !usesInProcessRuntime { return "local WebKit/WASM (in-process JIT unavailable)" }
        if inProcessUnavailable { return "in-process JavaScriptCore/WASM unavailable (no JIT)" }
        return usesInProcessRuntime ? "in-process JavaScriptCore/WASM (rootless dynamic-codesigning)" : "local WebKit/WASM"
    }
    var diagnosticSummary: String {
        let state = "Local signer: runtime=\(runtimeDescription); stage=\(stage); index=\(stageIndex); web_content_exit=\(lastWebContentExit)"
        return state + "\nRuntime events: " + recentEvents.joined(separator: " | ")
    }
    private func recordStage(_ label: String) {
        // Only record fixed, user-safe stage names and numeric error codes.
        recentEvents.append(label)
        if recentEvents.count > 24 { recentEvents.removeFirst(recentEvents.count - 24) }
    }

    /// Set around work the user is waiting for (getting an app, signing in).
    /// It goes ahead of background work such as reading version details.
    @TaskLocal static var userInitiated = false
    private struct Waiter {
        let id: UUID
        let urgent: Bool
        let continuation: CheckedContinuation<Void, Error>
    }
    /// Operations waiting for the runtime, served urgent first, then in order.
    private var waiters: [Waiter] = []
    /// How long an idle runtime is kept. Loading it again takes seconds.
    private static let idleKeepSeconds: UInt64 = 300

    override init() {
        super.init()
        memoryObserver = Publishers.Merge(
            NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification),
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification))
            .sink { [weak self] notification in
                let memoryWarning = notification.name == UIApplication.didReceiveMemoryWarningNotification
                Task { @MainActor in
                    guard let self else { return }
                    if self.operationID != nil {
                        // Never tear down the active SAP proxy as soon as the
                        // heavyweight WebKit/WASM runtime raises a memory warning.
                        // Cancelling its loopback listener here breaks signing.
                        self.recordStage(memoryWarning
                            ? "memory-warning-active-preserved" : "background-event-active")
                        return
                    }
                    self.discardIdleRuntime()
                    await self.server.reset()
                }
            }
    }

    func sign(_ data: Data, guid: String, useCache: Bool, cacheSignature: Bool = true, progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        let key = guid + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try Task.checkCancellation()
        if useCache, cacheSignature, let cached = signatureCache[key] { return cached }
        let revision = cacheRevision
        let result = try await execute(title: AppText.text("验证请求"), script: """
            reportStage(1);
            await sapInitialize(guid, {proxyURL: proxy});
            try { reportStage(2); return await sapSign(body); }
            finally { await sapClose(); }
            """, arguments: ["guid": guid, "body": data.base64EncodedString()], reuseRuntime: useCache, progress: progress)
        if useCache, cacheSignature, revision == cacheRevision {
            if signatureCache.count >= 128 { signatureCache.removeAll() }
            signatureCache[key] = result
        }
        return result
    }

    func kbsync(guid: String, dsid: String, useCache: Bool) async throws -> String {
        guard guid.count == 12, guid.allSatisfy(\.isHexDigit), let value = UInt64(dsid), value > 0 else {
            throw ToolError.message(AppText.text("设备标识或账号标识无效，请重新登录"))
        }
        try Task.checkCancellation()
        let key = guid + ":" + dsid
        if useCache, let cached = kbCache[key] { return cached }
        let revision = cacheRevision
        let result = try await execute(title: AppText.text("准备下载"), script: """
            reportStage(1);
            await loadSapSigner();
            reportStage(2);
            return await sapGenerateKBSync(guid, dsid);
            """, arguments: ["guid": guid, "dsid": dsid], reuseRuntime: useCache)
        if useCache, revision == cacheRevision { kbCache[key] = result }
        return result
    }

    private struct StoreStatePayload: Codable {
        var identifier: String
        var files: [String: String]
    }

    private struct StoreProofPayload: Decodable {
        var provisioned: Bool
        var headers: [String: String]?
        var state: StoreStatePayload
    }

    private static func normalizedStoreGUID(_ guid: String) throws -> String {
        let cleaned = guid.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .uppercased()
        guard cleaned.count == 12, cleaned.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw ToolError.message(AppText.text("设备标识无效，请检查专业模式设置"))
        }
        return cleaned
    }

    private static func derivedStoreIdentifier(guid: String) -> String {
        let digest = SHA256.hash(data: Data(("iPadn-store-id:" + guid).utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func randomStoreIdentifier() -> String {
        (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    private func currentStoreRecords() -> [String: StoreProofRecord] {
        if let loaded = storeProofRecords { return loaded }
        let loaded = StoreProofStore.load()
        storeProofRecords = loaded
        return loaded
    }

    private func record(for normalizedGUID: String) -> StoreProofRecord {
        if let existing = currentStoreRecords()[normalizedGUID],
           existing.identifier.count == 16,
           existing.identifier.allSatisfy({ $0.isASCII && $0.isHexDigit }) {
            return existing
        }
        return StoreProofRecord(identifier: Self.derivedStoreIdentifier(guid: normalizedGUID), files: [:])
    }

    private func saveRecord(_ record: StoreProofRecord, for normalizedGUID: String) throws {
        var all = currentStoreRecords()
        var updated = record
        updated.updatedAt = Date()
        all[normalizedGUID] = updated
        storeProofRecords = all
        try StoreProofStore.save(all)
    }

    func storeProofHeaders(guid: String, useCache: Bool) async throws -> [String: String]? {
        let normalized = try Self.normalizedStoreGUID(guid)
        try Task.checkCancellation()
        let existing = record(for: normalized)
        guard !existing.files.isEmpty else { return nil }
        let stateData = try JSONEncoder().encode(StoreStatePayload(identifier: existing.identifier, files: existing.files))
        guard let stateJSON = String(data: stateData, encoding: .utf8) else { return nil }
        let output = try await execute(title: AppText.text("验证设备"), script: """
            reportStage(1);
            reportStage(2);
            return await sapStoreProofHeaders(state, {proxyURL: proxy});
            """, arguments: ["state": stateJSON], reuseRuntime: useCache)
        let payload = try JSONDecoder().decode(StoreProofPayload.self, from: Data(output.utf8))
        if payload.state.identifier != existing.identifier || payload.state.files != existing.files {
            try saveRecord(StoreProofRecord(identifier: payload.state.identifier, files: payload.state.files), for: normalized)
        }
        guard payload.provisioned,
              let headers = payload.headers,
              let otp = headers["X-Apple-AMD"], !otp.isEmpty,
              let mid = headers["X-Apple-AMD-M"], !mid.isEmpty else {
            return nil
        }
        return ["X-Apple-AMD": otp, "X-Apple-AMD-M": mid]
    }

    func provisionStoreProof(challenge: String, guid: String, useCache: Bool) async throws -> [String: String] {
        let normalized = try Self.normalizedStoreGUID(guid)
        guard !challenge.isEmpty else { throw ToolError.message(AppText.text("设备验证参数无效，请稍后重试")) }
        try Task.checkCancellation()
        let current = record(for: normalized)
        let stateData = try JSONEncoder().encode(StoreStatePayload(identifier: current.identifier, files: current.files))
        guard let stateJSON = String(data: stateData, encoding: .utf8) else {
            throw ToolError.message(AppText.text("设备验证状态编码失败"))
        }
        let output = try await execute(title: AppText.text("验证设备"), script: """
            reportStage(1);
            reportStage(2);
            return await sapStoreProvision(state, challenge, guid, {proxyURL: proxy});
            """, arguments: ["state": stateJSON, "challenge": challenge, "guid": normalized], reuseRuntime: useCache)
        let payload = try JSONDecoder().decode(StoreProofPayload.self, from: Data(output.utf8))
        guard payload.provisioned,
              let headers = payload.headers,
              let otp = headers["X-Apple-AMD"], !otp.isEmpty,
              let mid = headers["X-Apple-AMD-M"], !mid.isEmpty else {
            throw ToolError.message(AppText.text("设备验证未完成，请稍后重试"))
        }
        try saveRecord(StoreProofRecord(identifier: payload.state.identifier, files: payload.state.files), for: normalized)
        return ["X-Apple-AMD": otp, "X-Apple-AMD-M": mid]
    }

    func resetStoreProof(guid: String) throws {
        guard let normalized = try? Self.normalizedStoreGUID(guid) else { return }
        try saveRecord(StoreProofRecord(identifier: Self.randomStoreIdentifier(), files: [:]), for: normalized)
    }

    private enum RuntimeRetry: Error { case coldStart }

    func execute(title: String, script: String, arguments: [String: Any], timeoutSeconds: UInt64 = 180, reuseRuntime: Bool = true, progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        do {
            return try await executeAttempt(title: title, script: script, arguments: arguments, timeoutSeconds: timeoutSeconds, reuseRuntime: reuseRuntime, progress: progress)
        } catch {
            // executeAttempt's defer must release the operation before a retry
            // can acquire it. Retrying inside that attempt deadlocks on itself.
            try Task.checkCancellation()
            if error is RuntimeRetry {
                return try await executeAttempt(title: title, script: script, arguments: arguments, timeoutSeconds: timeoutSeconds, reuseRuntime: false, progress: progress)
            }
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && (ns.code == NSURLErrorCannotConnectToHost || ns.code == NSURLErrorNetworkConnectionLost) {
                InstallLog.shared.add("SAPSigner loopback error (\(ns.code)), resetting server and retrying")
                await server.reset()
                discardIdleRuntime()
                return try await executeAttempt(title: title, script: script, arguments: arguments, timeoutSeconds: timeoutSeconds, reuseRuntime: false, progress: progress)
            }
            throw error
        }
    }

    private func executeAttempt(title: String, script: String, arguments: [String: Any], timeoutSeconds: UInt64 = 180, reuseRuntime: Bool = true, progress: @escaping @Sendable (String) -> Void) async throws -> String {
        // One operation at a time: wait for the current one (for example a
        // background purchase sync) instead of failing the user's action.
        // Waiting in a queue, not polling: a busy background loop must not
        // keep taking the runtime before a waiting user action gets it.
        try await acquireTurn()
        let id = UUID(); operationID = id; terminalError = nil
        recentEvents.removeAll()
        lastWebContentExit = false
        recordStage("operation-start")
        let revision = cacheRevision
        var succeeded = false
        idleTimeout?.cancel(); idleTimeout = nil
        self.title = title; stage = AppText.text("准备本地环境"); stageIndex = 0; startedAt = Date()
        defer { release(id: id, reuse: reuseRuntime && succeeded && cacheRevision == revision) }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            progress("Preparing local authentication runtime")
            recordStage("assets-preparing")
            try await RuntimeAssets.prepare(progress: progress)
            recordStage("assets-ready")
            try Task.checkCancellation()
            progress("Starting local signing service")
            recordStage("loopback-starting")
            try await server.start()
            recordStage("loopback-ready")
            try checkActive(id)
            guard let base = server.baseURL else { throw ToolError.message(AppText.text("暂时无法完成验证，请重试")) }
            if usesInProcessRuntime {
                do {
                    let result = try await executeInProcess(id: id, base: base, script: script, arguments: arguments,
                                                            timeoutSeconds: timeoutSeconds, reuseRuntime: reuseRuntime, progress: progress)
                    succeeded = true
                    return result
                } catch InProcessSAPRuntime.Failure.webAssemblyUnavailable {
                    // No JIT for JavaScriptCore in this install (for example a
                    // DEB signed without dynamic-codesigning). Use WebKit.
                    inProcessUnavailable = true
                    recordStage("jsc-wasm-unavailable")
                    try checkActive(id)
                }
            }
            let web: WKWebView
            let warm = reuseRuntime && reusableBase == base && reusableWebView != nil
            if warm, let saved = reusableWebView { web = saved }
            else {
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()
                web = WKWebView(frame: .zero, configuration: config)
            }
            reusableWebView = nil; reusableBase = nil
            web.customUserAgent = StoreProtocol.userAgent
            web.configuration.userContentController.add(self, name: "progress")
            web.navigationDelegate = self
            webView = web; isPresented = true
            recordStage("webview-attaching")
            // Give SwiftUI an opportunity to attach the signer WKWebView at a
            // normal visible size before starting expensive WebAssembly.
            await Task.yield()
            // WebContent may already have terminated while attaching.
            try checkActive(id)
            if !warm {
                armTimeout(id: id, seconds: 45, message: AppText.text("本地验证环境加载超时，请重试。"))
                progress("Loading local authentication page")
                recordStage("navigation-starting")
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    navigation = continuation
                    web.load(URLRequest(url: base.appendingPathComponent("runtime/index.html")))
                }
            } else {
                stage = AppText.text("复用本机验证组件")
            }
            try checkActive(id)
            armTimeout(id: id, seconds: timeoutSeconds, message: AppText.text("验证已超过 3 分钟，已停止本次操作。请保持应用在前台后重试。"))
            progress("Signing Apple authentication request")
            recordStage("javascript-starting")
            var values = arguments
            values["proxy"] = base.appendingPathComponent("proxy").absoluteString
            let result: String
            do {
                result = try await withCheckedThrowingContinuation { continuation in
                    evaluation = continuation
                    web.callAsyncJavaScript(script, arguments: values, in: nil, in: .page) { [weak self] result in
                        Task { @MainActor in
                            guard let self, self.operationID == id, let continuation = self.evaluation else { return }
                            self.evaluation = nil
                            switch result {
                            case .success(let value):
                                self.recordStage("javascript-completed")
                                if let text = value as? String, !text.isEmpty { continuation.resume(returning: text) }
                                else { continuation.resume(throwing: ToolError.message(AppText.text("验证结果为空，请重试"))) }
                            case .failure(let err):
                                self.recordStage("javascript-error-\((err as NSError).code)")
                                continuation.resume(throwing: err)
                            }
                        }
                    }
                }
            } catch {
                // Preserve explicit cancellation and timeout errors; neither is
                // evidence of a stale cached WebKit runtime.
                try checkActive(id)
                if warm {
                    discardIdleRuntime()
                    throw RuntimeRetry.coldStart
                }
                // Preserve the underlying error code without disclosing the
                // contents of JavaScript exceptions or account information.
                let issue = error as NSError
                if let runtime = error as? ToolError { throw runtime }
                let domain = issue.domain == "WKErrorDomain" ? "WebKit" : "local signer"
                throw ToolError.message("Local Apple signing failed (\(domain) code \(issue.code)). Check the authentication stage in Settings > Backend Report.")
            }
            try checkActive(id)
            succeeded = true
            return result
        } onCancel: { [weak self] in
            Task { @MainActor in self?.stop(id: id, error: CancellationError()) }
        }
    }

    private func executeInProcess(id: UUID, base: URL, script: String, arguments: [String: Any], timeoutSeconds: UInt64, reuseRuntime: Bool, progress: @escaping @Sendable (String) -> Void) async throws -> String {
        let warm = reuseRuntime && inProcessBase == base && inProcessRuntime?.isAlive == true
        let runtime: InProcessSAPRuntime
        if warm, let saved = inProcessRuntime {
            runtime = saved
            stage = AppText.text("复用本机验证组件")
        } else {
            discardInProcessRuntime()
            armTimeout(id: id, seconds: 45, message: AppText.text("本地验证环境加载超时，请重试。"))
            progress("Loading local authentication engine")
            recordStage("jsc-runtime-starting")
            runtime = try await InProcessSAPRuntime.make(serverBase: base) { index in
                Task { @MainActor in LocalSAPSigner.shared.applyStage(index) }
            }
            guard operationID == id, terminalError == nil else { runtime.shutdown(); try checkActive(id); throw CancellationError() }
            inProcessRuntime = runtime; inProcessBase = base
            recordStage("jsc-runtime-ready")
        }
        try checkActive(id)
        armTimeout(id: id, seconds: timeoutSeconds, message: AppText.text("验证已超过 3 分钟，已停止本次操作。请保持应用在前台后重试。"))
        progress("Signing Apple authentication request")
        recordStage("javascript-starting")
        var values: [String: String] = [:]
        for (key, value) in arguments { values[key] = (value as? String) ?? String(describing: value) }
        values["proxy"] = base.appendingPathComponent("proxy").absoluteString
        do {
            return try await withCheckedThrowingContinuation { continuation in
                evaluation = continuation
                runtime.call(script: script, arguments: values) { result in
                    Task { @MainActor [weak self] in
                        guard let self, self.operationID == id, let continuation = self.evaluation else { return }
                        self.evaluation = nil
                        switch result {
                        case .success(let text):
                            self.recordStage("javascript-completed")
                            continuation.resume(returning: text)
                        case .failure(let failure):
                            self.recordStage("javascript-error-jsc")
                            continuation.resume(throwing: failure)
                        }
                    }
                }
            }
        } catch {
            try checkActive(id)
            // A failed operation can leave the signer's internal state open.
            discardInProcessRuntime()
            if warm { throw RuntimeRetry.coldStart }
            throw error
        }
    }

    private func applyStage(_ index: Int) {
        guard operationID != nil, (1...2).contains(index) else { return }
        stageIndex = index
        recordStage("javascript-stage-\(index)")
        stage = index == 1 ? AppText.text("加载验证组件")
            : title == AppText.text("准备下载") ? AppText.text("生成下载授权数据")
            : title == AppText.text("验证设备") ? AppText.text("完成设备安全验证") : AppText.text("生成请求签名")
    }

    private func discardInProcessRuntime() {
        inProcessRuntime?.shutdown()
        inProcessRuntime = nil; inProcessBase = nil
    }

    private func acquireTurn() async throws {
        try Task.checkCancellation()
        guard operationID != nil || !waiters.isEmpty else { return }
        let ticket = UUID()
        let urgent = Self.userInitiated
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let waiter = Waiter(id: ticket, urgent: urgent, continuation: continuation)
                // Urgent requests line up after other urgent ones, ahead of background work.
                if urgent, let index = waiters.firstIndex(where: { !$0.urgent }) { waiters.insert(waiter, at: index) }
                else { waiters.append(waiter) }
                // Freed while this was being queued.
                if operationID == nil { handOver() }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, let index = self.waiters.firstIndex(where: { $0.id == ticket }) else { return }
                self.waiters.remove(at: index).continuation.resume(throwing: CancellationError())
            }
        }
    }
    /// Gives the free runtime to the next waiter. Its operation takes
    /// operationID right away, before anyone else can.
    private func handOver() {
        guard operationID == nil, !waiters.isEmpty else { return }
        operationID = UUID()
        waiters.removeFirst().continuation.resume()
    }
    private func checkActive(_ id: UUID) throws {
        try Task.checkCancellation()
        if let terminalError { throw terminalError }
        guard operationID == id else { throw CancellationError() }
    }
    private func armTimeout(id: UUID, seconds: UInt64, message: String) {
        timeout?.cancel()
        timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            self?.stop(id: id, error: ToolError.message(message))
        }
    }
    private func finishNavigation(_ result: Result<Void, Error>) {
        let continuation = navigation; navigation = nil
        continuation?.resume(with: result)
    }
    private func stop(id: UUID, error: Error) {
        guard operationID == id else { return }
        terminalError = error
        finishNavigation(.failure(error))
        let continuation = evaluation; evaluation = nil
        continuation?.resume(throwing: error)
        timeout?.cancel()
        // An interrupted in-process operation may still be running; never reuse it.
        discardInProcessRuntime()
        webView?.stopLoading()
        webView?.loadHTMLString("<!doctype html><title>Stopped</title>", baseURL: nil)
        isPresented = false
    }
    func cancel() {
        if let id = operationID { stop(id: id, error: CancellationError()) }
    }
    private func release(id: UUID, reuse: Bool) {
        guard operationID == id else { return }
        timeout?.cancel(); timeout = nil
        finishNavigation(.failure(CancellationError()))
        let continuation = evaluation; evaluation = nil
        continuation?.resume(throwing: CancellationError())
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "progress")
        webView?.stopLoading(); webView?.navigationDelegate = nil
        if reuse && UIApplication.shared.applicationState != .background {
            reusableWebView = webView; reusableBase = server.baseURL
            idleTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: Self.idleKeepSeconds * 1_000_000_000) } catch { return }
                self?.discardIdleRuntime()
            }
        } else {
            reusableWebView = nil; reusableBase = nil
            discardInProcessRuntime()
        }
        webView = nil
        isPresented = false; operationID = nil; terminalError = nil
        handOver()
    }
    private func discardIdleRuntime() {
        guard operationID == nil else { return }
        idleTimeout?.cancel(); idleTimeout = nil
        reusableWebView?.stopLoading(); reusableWebView = nil; reusableBase = nil
        discardInProcessRuntime()
    }
    func clearCache() { cacheRevision = UUID(); signatureCache.removeAll(); kbCache.removeAll(); discardIdleRuntime() }

    /// Loads the runtime ahead of a likely request (an app page opened), so
    /// getting the app does not wait for it. Does nothing if it is loaded or busy.
    func prewarm() {
        guard operationID == nil, waiters.isEmpty, inProcessRuntime == nil,
              UIApplication.shared.applicationState == .active else { return }
        guard reusableWebView == nil else { return }
        Task { _ = try? await execute(title: "准备验证组件", script: "return 'ready';", arguments: [:], timeoutSeconds: 30) }
    }
}

extension LocalSAPSigner: WKNavigationDelegate, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === webView, let index = message.body as? Int else { return }
        applyStage(index)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let target = navigationAction.request.url, let base = server.baseURL,
              target.scheme == base.scheme, target.host == "127.0.0.1", target.port == base.port,
              target.path.hasPrefix(base.path) else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, terminalError == nil else { return }
        recordStage("navigation-complete")
        finishNavigation(.success(()))
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        recordStage("navigation-error-\((error as NSError).code)")
        finishNavigation(.failure(error))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }; finishNavigation(.failure(error))
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView, let id = operationID else { return }
        lastWebContentExit = true
        recordStage("WEB_CONTENT_EXIT")
        stop(id: id, error: ToolError.message("WebKit authentication process terminated (WEB_CONTENT_EXIT). The local signer stopped before Apple's login/2FA response; see Settings > Backend Report."))
    }
}
