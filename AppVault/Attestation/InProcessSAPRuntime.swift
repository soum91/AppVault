import Foundation
import JavaScriptCore
import Security

/// Runs the pinned SAP runtime in an in-process JavaScriptCore context.
///
/// Used by the rootless jailbreak DEB only. On Dopamine/iOS 16 the WebKit
/// WebContent process serving the signer page terminated as soon as it was
/// spawned (WEB_CONTENT_EXIT before navigation). The DEB is signed with
/// `dynamic-codesigning`, which lets JavaScriptCore enable its JIT and
/// WebAssembly inside AppVault itself, so no WebContent process is needed.
/// The sideloaded IPA cannot have that entitlement and keeps using WebKit.
///
/// The runtime loads the same hash-verified files from the same loopback
/// server, and its network access is limited to that server (runtime files
/// and the three-endpoint Apple proxy), as with the WebKit page.
final class InProcessSAPRuntime: @unchecked Sendable {
    enum Failure: Error {
        /// JavaScriptCore was not given JIT/WebAssembly (missing entitlement).
        case webAssemblyUnavailable
    }

    /// Scripts the runtime may load, all pinned in RuntimeAssets.
    private static let loadableScripts: Set<String> = ["unicorn_x86.js", "wasm_exec.js"]

    private let thread = RuntimeThread()
    private let documentURL: String
    private let loopbackRoot: String
    private let onStage: @Sendable (Int) -> Void
    private let session: URLSession
    private let startedAt = CFAbsoluteTimeGetCurrent()
    // Touched only on `thread`.
    private var context: JSContext?
    private var timers: [Int: JSValue] = [:]
    private var nextTimer = 0
    private let stateLock = NSLock()
    private var isShutDown = false

    private init(serverBase: URL, onStage: @escaping @Sendable (Int) -> Void) {
        var root = serverBase.absoluteString
        if !root.hasSuffix("/") { root += "/" }
        loopbackRoot = root
        documentURL = root + "runtime/index.html"
        self.onStage = onStage
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration)
        // Unicorn and the Go WASM runtime recurse deeply; a GCD thread's
        // 512 KB stack is not enough headroom for JavaScriptCore.
        thread.stackSize = 16 << 20
        thread.name = "com.soum91.appvault.sap-runtime"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Creates the context, installs the browser shims and loads sap-signer.js.
    static func make(serverBase: URL, onStage: @escaping @Sendable (Int) -> Void) async throws -> InProcessSAPRuntime {
        let runtime = InProcessSAPRuntime(serverBase: serverBase, onStage: onStage)
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                runtime.thread.perform {
                    do { try runtime.setUp(); continuation.resume() }
                    catch { continuation.resume(throwing: error) }
                }
            }
            return runtime
        } catch {
            runtime.shutdown()
            throw error
        }
    }

    var isAlive: Bool { stateLock.lock(); defer { stateLock.unlock() }; return !isShutDown }

    /// Runs `script` as the body of an async function whose parameters are the
    /// argument names, like WKWebView.callAsyncJavaScript. Completion runs on
    /// the runtime thread.
    func call(script: String, arguments: [String: String], completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        thread.perform { [self] in
            guard let context, isAlive else { completion(.failure(CancellationError())); return }
            let names = arguments.keys.sorted()
            guard names.allSatisfy(Self.isIdentifier) else {
                completion(.failure(ToolError.message("Local signer received an invalid argument name."))); return
            }
            let finished = OnceFlag()
            let source = "(async function(" + names.joined(separator: ", ") + ") {\n" + script + "\n})"
            context.exception = nil
            guard let function = context.evaluateScript(source), context.exception == nil else {
                let detail = Self.safeDescription(context.exception)
                context.exception = nil
                completion(.failure(ToolError.message("Local signer script could not start (\(detail)).")))
                return
            }
            let onSuccess: @convention(block) (JSValue) -> Void = { value in
                guard finished.claim() else { return }
                if value.isString, let text = value.toString(), !text.isEmpty { completion(.success(text)) }
                else { completion(.failure(ToolError.message(AppText.text("验证结果为空，请重试")))) }
            }
            let onFailure: @convention(block) (JSValue) -> Void = { reason in
                guard finished.claim() else { return }
                completion(.failure(ToolError.message("Local Apple signing failed in the in-process runtime (\(Self.safeDescription(reason))). Check Settings > Backend Report.")))
            }
            let promise = function.call(withArguments: names.map { arguments[$0] ?? "" })
            if let exception = context.exception {
                context.exception = nil
                if finished.claim() {
                    completion(.failure(ToolError.message("Local signer script failed (\(Self.safeDescription(exception))).")))
                }
                return
            }
            _ = promise?.invokeMethod("then", withArguments: [JSValue(object: onSuccess, in: context) as Any,
                                                          JSValue(object: onFailure, in: context) as Any])
            context.exception = nil
        }
    }

    func shutdown() {
        stateLock.lock()
        if isShutDown { stateLock.unlock(); return }
        isShutDown = true
        stateLock.unlock()
        session.invalidateAndCancel()
        thread.perform { [self] in
            timers.removeAll()
            context = nil
            thread.finish()
        }
    }

    // MARK: - Setup (runtime thread)

    private func setUp() throws {
        guard let machine = JSVirtualMachine(), let context = JSContext(virtualMachine: machine) else {
            throw ToolError.message("Local signer could not create a JavaScript context.")
        }
        context.name = "AppVault SAP runtime"
        self.context = context
        installNatives(in: context)
        context.evaluateScript(Self.prelude, withSourceURL: URL(string: "appvault://runtime/prelude.js"))
        if let exception = context.exception {
            context.exception = nil
            throw ToolError.message("Local signer shims failed to load (\(Self.safeDescription(exception))).")
        }
        let wasm = context.evaluateScript("typeof WebAssembly === 'object' && typeof WebAssembly.instantiate === 'function'")
        guard wasm?.toBool() == true else { throw Failure.webAssemblyUnavailable }
        let signerURL = RuntimeAssets.directory.appendingPathComponent("sap-signer.js")
        guard let signer = try? String(contentsOf: signerURL, encoding: .utf8) else {
            throw ToolError.message("Local signer component sap-signer.js is missing; reopen AppVault and retry.")
        }
        context.evaluateScript(signer, withSourceURL: URL(string: documentURL)?.deletingLastPathComponent().appendingPathComponent("sap-signer.js"))
        if let exception = context.exception {
            context.exception = nil
            throw ToolError.message("Local signer component failed to load (\(Self.safeDescription(exception))).")
        }
        guard context.evaluateScript("typeof sapInitialize === 'function' && typeof sapGenerateKBSync === 'function'")?.toBool() == true else {
            throw ToolError.message("Local signer component did not register its functions.")
        }
    }

    private func installNatives(in context: JSContext) {
        context.setObject(documentURL, forKeyedSubscript: "__avBaseURI" as NSString)

        let resolveURL: @convention(block) (String, JSValue) -> String = { input, base in
            let baseURL = base.isString ? base.toString().flatMap { URL(string: $0) } : nil
            guard let url = URL(string: input, relativeTo: baseURL)?.absoluteURL, url.scheme != nil else { return "" }
            return url.absoluteString
        }
        context.setObject(resolveURL, forKeyedSubscript: "__avResolveURL" as NSString)

        let now: @convention(block) () -> Double = { [startedAt] in (CFAbsoluteTimeGetCurrent() - startedAt) * 1000 }
        context.setObject(now, forKeyedSubscript: "__avNow" as NSString)

        let random: @convention(block) (Double) -> JSValue = { [weak self, weak context] count in
            guard let self, let context else { return JSValue(undefinedIn: JSContext.current()) }
            var data = Data(count: max(0, min(65536, Int(count))))
            let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
            if status != errSecSuccess { context.exception = JSValue(newErrorFromMessage: "Secure random generation failed", in: context) }
            return self.arrayBuffer(data, in: context)
        }
        context.setObject(random, forKeyedSubscript: "__avRandom" as NSString)

        let encode: @convention(block) (String) -> JSValue = { [weak self, weak context] text in
            guard let self, let context else { return JSValue(undefinedIn: JSContext.current()) }
            return self.arrayBuffer(Data(text.utf8), in: context)
        }
        context.setObject(encode, forKeyedSubscript: "__avUTF8Encode" as NSString)

        let decode: @convention(block) (JSValue, Double, Double) -> String = { [weak self] buffer, offset, length in
            guard let self, let data = self.bytes(of: buffer, offset: Int(offset), length: Int(length)) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
        context.setObject(decode, forKeyedSubscript: "__avUTF8Decode" as NSString)

        let schedule: @convention(block) (Double, JSValue) -> Double = { [weak self] delay, callback in
            guard let self else { return 0 }
            nextTimer += 1
            let id = nextTimer
            timers[id] = callback
            let fire: @Sendable () -> Void = { [weak self] in
                self?.thread.perform {
                    guard let self, let callback = self.timers.removeValue(forKey: id) else { return }
                    callback.call(withArguments: [])
                    self.context?.exception = nil
                }
            }
            if delay <= 0 { fire() }
            else { DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay / 1000, execute: fire) }
            return Double(id)
        }
        context.setObject(schedule, forKeyedSubscript: "__avSchedule" as NSString)

        let cancel: @convention(block) (Double) -> Void = { [weak self] id in _ = self?.timers.removeValue(forKey: Int(id)) }
        context.setObject(cancel, forKeyedSubscript: "__avCancel" as NSString)

        let stage: @convention(block) (Double) -> Void = { [onStage] index in onStage(Int(index)) }
        context.setObject(stage, forKeyedSubscript: "__avStage" as NSString)

        let loadScript: @convention(block) (String) -> Bool = { [weak self, weak context] address in
            guard let self, let context,
                  address.hasPrefix(self.loopbackRoot + "runtime/"),
                  let name = URL(string: address)?.lastPathComponent,
                  Self.loadableScripts.contains(name),
                  let source = try? String(contentsOf: RuntimeAssets.directory.appendingPathComponent(name), encoding: .utf8)
            else { return false }
            context.evaluateScript(source, withSourceURL: URL(string: address))
            if context.exception != nil { context.exception = nil; return false }
            return true
        }
        context.setObject(loadScript, forKeyedSubscript: "__avLoadScript" as NSString)

        let fetch: @convention(block) (String, String, String, JSValue, Double, Double, JSValue) -> Void = { [weak self] address, method, headersJSON, body, offset, length, callback in
            self?.fetch(address: address, method: method, headersJSON: headersJSON, body: body,
                        offset: Int(offset), length: Int(length), callback: callback)
        }
        context.setObject(fetch, forKeyedSubscript: "__avFetch" as NSString)
    }

    // MARK: - Native fetch (runtime thread)

    private func fetch(address: String, method: String, headersJSON: String, body: JSValue, offset: Int, length: Int, callback: JSValue) {
        func reply(_ status: Int, _ data: Data?, _ headers: String, _ error: String?) {
            thread.perform { [weak self] in
                guard let self, let context = self.context else { return }
                let buffer: Any = data.map { self.arrayBuffer($0, in: context) } ?? NSNull()
                callback.call(withArguments: [status, buffer, headers, error ?? NSNull()])
                context.exception = nil
            }
        }
        // Same reach as the WebKit page: the loopback runtime files and proxy only.
        guard address.hasPrefix(loopbackRoot), let url = URL(string: address), url.host == "127.0.0.1" else {
            reply(0, nil, "{}", "blocked non-local request"); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = ["GET", "POST", "HEAD"].contains(method) ? method : "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let data = headersJSON.data(using: .utf8),
           let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        }
        if request.httpMethod == "POST", !body.isNull, !body.isUndefined {
            guard let payload = bytes(of: body, offset: offset, length: length) else {
                reply(0, nil, "{}", "invalid request body"); return
            }
            request.httpBody = payload
        }
        session.dataTask(with: request) { data, response, error in
            if let error {
                reply(0, nil, "{}", "network error \((error as NSError).code)"); return
            }
            let http = response as? HTTPURLResponse
            var headers: [String: String] = [:]
            http?.allHeaderFields.forEach { key, value in headers[String(describing: key)] = String(describing: value) }
            let json = (try? JSONSerialization.data(withJSONObject: headers)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            reply(http?.statusCode ?? 0, data ?? Data(), json, nil)
        }.resume()
    }

    // MARK: - ArrayBuffer bridging

    private func arrayBuffer(_ data: Data, in context: JSContext) -> JSValue {
        let count = data.count
        guard let memory = malloc(max(count, 1)) else { return JSValue(nullIn: context) }
        if count > 0 { data.copyBytes(to: memory.assumingMemoryBound(to: UInt8.self), count: count) }
        var exception: JSValueRef?
        guard let object = JSObjectMakeArrayBufferWithBytesNoCopy(context.jsGlobalContextRef, memory, count,
                                                                  { bytes, _ in free(bytes) }, nil, &exception) else {
            free(memory)
            return JSValue(nullIn: context)
        }
        return JSValue(jsValueRef: object, in: context)
    }

    /// Copies `length` bytes at `offset` out of a JavaScript ArrayBuffer.
    private func bytes(of value: JSValue, offset: Int, length: Int) -> Data? {
        guard let context = value.context, offset >= 0, length >= 0 else { return nil }
        let ref = context.jsGlobalContextRef
        guard JSValueGetTypedArrayType(ref, value.jsValueRef, nil) == kJSTypedArrayTypeArrayBuffer,
              let object = JSValueToObject(ref, value.jsValueRef, nil) else { return nil }
        let total = JSObjectGetArrayBufferByteLength(ref, object, nil)
        guard offset <= total, length <= total - offset else { return nil }
        if length == 0 { return Data() }
        guard let base = JSObjectGetArrayBufferBytesPtr(ref, object, nil) else { return nil }
        return Data(bytes: base.advanced(by: offset), count: length)
    }

    // MARK: - Helpers

    private static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, CharacterSet.letters.contains(first) || first == "_" else { return false }
        return name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" } && name.unicodeScalars.allSatisfy(\.isASCII)
    }

    /// A short, credentials-free description of a JavaScript error: its type
    /// and, only when it looks like a fixed diagnostic phrase, its message.
    /// Anything with paths, URLs, long tokens or data is dropped.
    static func safeDescription(_ value: JSValue?) -> String {
        guard let value, !value.isUndefined, !value.isNull else { return "unknown error" }
        let name = value.isObject ? (value.forProperty("name")?.toString() ?? "Error") : "Error"
        let safeName = name.range(of: "^[A-Za-z]{1,32}$", options: .regularExpression) != nil ? name : "Error"
        let message = value.isObject ? (value.forProperty("message")?.toString() ?? "") : (value.toString() ?? "")
        let allowed = message.range(of: "^[A-Za-z0-9 .,:'()_-]{1,120}$", options: .regularExpression) != nil
        let tokenLike = message.range(of: "[A-Za-z0-9+_-]{24,}", options: .regularExpression) != nil
        return allowed && !tokenLike ? safeName + ": " + message : safeName
    }

    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
    }

    /// A thread with its own run loop, so JavaScriptCore always runs on one
    /// thread with a large stack.
    private final class RuntimeThread: Thread {
        private let condition = NSCondition()
        private var loop: CFRunLoop?
        override func main() {
            condition.lock(); loop = CFRunLoopGetCurrent(); condition.broadcast(); condition.unlock()
            RunLoop.current.add(NSMachPort(), forMode: .default)
            while !isCancelled {
                autoreleasepool { _ = RunLoop.current.run(mode: .default, before: .distantFuture) }
            }
        }
        func perform(_ block: @escaping () -> Void) {
            condition.lock()
            while loop == nil { condition.wait() }
            let target = loop!
            condition.unlock()
            CFRunLoopPerformBlock(target, CFRunLoopMode.defaultMode.rawValue, block)
            CFRunLoopWakeUp(target)
        }
        /// Call on this thread.
        func finish() {
            cancel()
            if let loop { CFRunLoopStop(loop) }
        }
    }

    /// Browser surface for the pinned runtime. Tests/RuntimeUI/test_inprocess_prelude.cjs
    /// extracts and exercises this script in a bare JavaScript realm.
    static let prelude = #"""
(function (root) {
  "use strict";
  // Browser surface needed by the pinned SAP runtime (sap-signer.js,
  // unicorn_x86.js, wasm_exec.js) when it runs in an in-process JSContext
  // instead of a WebKit page. Native hooks are the __av* functions.
  const native = {
    resolveURL: root.__avResolveURL,
    fetch: root.__avFetch,
    utf8Encode: root.__avUTF8Encode,
    utf8Decode: root.__avUTF8Decode,
    random: root.__avRandom,
    now: root.__avNow,
    schedule: root.__avSchedule,
    cancel: root.__avCancel,
    loadScript: root.__avLoadScript,
    stage: root.__avStage,
    baseURI: root.__avBaseURI
  };

  function u8(input) {
    if (input === undefined || input === null) return new Uint8Array(0);
    if (input instanceof ArrayBuffer) return new Uint8Array(input);
    if (ArrayBuffer.isView(input)) return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    throw new TypeError("Expected an ArrayBuffer or ArrayBufferView");
  }

  // Timers
  root.setTimeout = function (fn, ms) {
    const args = Array.prototype.slice.call(arguments, 2);
    const delay = Math.max(0, Number(ms) || 0);
    return native.schedule(delay, function () { if (typeof fn === "function") fn.apply(root, args); });
  };
  root.clearTimeout = function (id) { if (id !== undefined && id !== null) native.cancel(Number(id)); };
  root.queueMicrotask = root.queueMicrotask || (fn => { Promise.resolve().then(fn); });

  root.performance = { now: () => native.now() };
  root.crypto = {
    getRandomValues(array) {
      if (!ArrayBuffer.isView(array)) throw new TypeError("getRandomValues requires a typed array");
      if (array.byteLength > 65536) throw new RangeError("getRandomValues quota exceeded");
      u8(array).set(new Uint8Array(native.random(array.byteLength)));
      return array;
    }
  };

  class TextEncoder {
    get encoding() { return "utf-8"; }
    encode(text) { return new Uint8Array(native.utf8Encode(String(text === undefined ? "" : text))); }
    encodeInto(text, dest) {
      const bytes = this.encode(text);
      const written = Math.min(bytes.length, dest.length);
      dest.set(bytes.subarray(0, written));
      return { read: written === bytes.length ? String(text).length : written, written };
    }
  }
  class TextDecoder {
    constructor(label) {
      const name = String(label === undefined ? "utf-8" : label).toLowerCase();
      if (name !== "utf-8" && name !== "utf8") throw new RangeError("Only UTF-8 is supported");
    }
    get encoding() { return "utf-8"; }
    decode(input) {
      const view = u8(input);
      if (view.byteLength === 0) return "";
      return native.utf8Decode(view.buffer, view.byteOffset, view.byteLength);
    }
  }
  root.TextEncoder = TextEncoder;
  root.TextDecoder = TextDecoder;

  const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  root.btoa = function (input) {
    const text = String(input);
    let out = "";
    for (let i = 0; i < text.length; i += 3) {
      const a = text.charCodeAt(i), b = text.charCodeAt(i + 1), c = text.charCodeAt(i + 2);
      if (a > 255 || b > 255 || c > 255) throw new Error("btoa: invalid character");
      const n = (a << 16) | ((b || 0) << 8) | (c || 0);
      out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] +
        (i + 1 < text.length ? B64[(n >> 6) & 63] : "=") +
        (i + 2 < text.length ? B64[n & 63] : "=");
    }
    return out;
  };
  root.atob = function (input) {
    const text = String(input).replace(/[\t\n\f\r ]+/g, "").replace(/=+$/, "");
    if (text.length % 4 === 1 || /[^A-Za-z0-9+/]/.test(text)) throw new Error("atob: invalid base64");
    let out = "", bits = 0, value = 0;
    for (let i = 0; i < text.length; i++) {
      value = (value << 6) | B64.indexOf(text[i]);
      bits += 6;
      if (bits >= 8) { bits -= 8; out += String.fromCharCode((value >> bits) & 255); }
    }
    return out;
  };

  // URL: resolution is native (Foundation); query editing is local.
  const encodeParam = s => encodeURIComponent(s).replace(/%20/g, "+");
  const decodeParam = s => decodeURIComponent(s.replace(/\+/g, " "));
  class URLSearchParamsLite {
    constructor(url) { this._url = url; }
    _pairs() {
      const q = this._url.search.replace(/^\?/, "");
      if (!q) return [];
      return q.split("&").filter(Boolean).map(part => {
        const at = part.indexOf("=");
        return at < 0 ? [decodeParam(part), ""] : [decodeParam(part.slice(0, at)), decodeParam(part.slice(at + 1))];
      });
    }
    _write(pairs) { this._url.search = pairs.map(([k, v]) => encodeParam(k) + "=" + encodeParam(v)).join("&"); }
    get(name) { const hit = this._pairs().find(p => p[0] === String(name)); return hit ? hit[1] : null; }
    has(name) { return this._pairs().some(p => p[0] === String(name)); }
    set(name, value) {
      const key = String(name);
      const pairs = this._pairs().filter(p => p[0] !== key);
      pairs.push([key, String(value)]);
      this._write(pairs);
    }
    append(name, value) { const pairs = this._pairs(); pairs.push([String(name), String(value)]); this._write(pairs); }
    toString() { return this._url.search.replace(/^\?/, ""); }
  }
  class URL {
    constructor(input, base) {
      const href = native.resolveURL(String(input), base === undefined ? null : String(base instanceof URL ? base.href : base));
      if (typeof href !== "string" || !href) throw new TypeError("Invalid URL: " + String(input));
      this._href = href;
      this.searchParams = new URLSearchParamsLite(this);
    }
    get href() { return this._href; }
    toString() { return this._href; }
    toJSON() { return this._href; }
    _split() {
      const hashAt = this._href.indexOf("#");
      const beforeHash = hashAt < 0 ? this._href : this._href.slice(0, hashAt);
      const hash = hashAt < 0 ? "" : this._href.slice(hashAt);
      const queryAt = beforeHash.indexOf("?");
      return {
        head: queryAt < 0 ? beforeHash : beforeHash.slice(0, queryAt),
        query: queryAt < 0 ? "" : beforeHash.slice(queryAt),
        hash
      };
    }
    get search() { const q = this._split().query; return q === "?" ? "" : q; }
    set search(value) {
      const parts = this._split();
      const text = String(value).replace(/^\?/, "");
      this._href = parts.head + (text ? "?" + text : "") + parts.hash;
    }
    get protocol() { return this._href.slice(0, this._href.indexOf(":") + 1); }
    get pathname() {
      const head = this._split().head;
      const afterScheme = head.indexOf("//") < 0 ? head : head.slice(head.indexOf("//") + 2);
      const slash = afterScheme.indexOf("/");
      return slash < 0 ? "/" : afterScheme.slice(slash);
    }
  }
  root.URL = URL;

  // fetch: bytes go through native networking (loopback runtime/proxy only).
  function bodyBytes(body) {
    if (body === undefined || body === null) return null;
    if (typeof body === "string") return new TextEncoder().encode(body);
    return u8(body);
  }
  function headerObject(headers) {
    const out = {};
    if (!headers) return out;
    if (typeof headers.forEach === "function" && !(headers instanceof Array)) {
      headers.forEach((v, k) => { out[String(k)] = String(v); });
    } else if (headers instanceof Array) {
      headers.forEach(([k, v]) => { out[String(k)] = String(v); });
    } else {
      Object.keys(headers).forEach(k => { out[k] = String(headers[k]); });
    }
    return out;
  }
  class ResponseLite {
    constructor(url, status, buffer, headers) {
      this.url = url; this.status = status; this.ok = status >= 200 && status < 300;
      this._buffer = buffer || new ArrayBuffer(0);
      const lower = {};
      Object.keys(headers || {}).forEach(k => { lower[k.toLowerCase()] = headers[k]; });
      this.headers = { get: name => lower[String(name).toLowerCase()] ?? null, has: name => String(name).toLowerCase() in lower };
    }
    async arrayBuffer() { return this._buffer; }
    async text() { return new TextDecoder().decode(this._buffer); }
    async json() { return JSON.parse(await this.text()); }
  }
  root.fetch = function (resource, init) {
    return new Promise((resolve, reject) => {
      try {
        const url = new URL(resource instanceof URL ? resource.href : String(resource), native.baseURI).href;
        const options = init || {};
        const method = String(options.method || "GET").toUpperCase();
        const body = bodyBytes(options.body);
        native.fetch(url, method, JSON.stringify(headerObject(options.headers)),
          body ? body.buffer : null, body ? body.byteOffset : 0, body ? body.byteLength : 0,
          (status, buffer, headersJSON, error) => {
            if (error) { reject(new TypeError("Load failed: " + error)); return; }
            let headers = {};
            try { headers = JSON.parse(headersJSON || "{}"); } catch (_) {}
            resolve(new ResponseLite(url, status, buffer, headers));
          });
      } catch (error) { reject(error); }
    });
  };

  // Minimal document so sap-signer resolves its base and loads its scripts.
  root.document = {
    baseURI: native.baseURI,
    currentScript: null,
    createElement() { return {}; },
    head: {
      appendChild(script) {
        root.setTimeout(() => {
          let loaded = false;
          try { loaded = native.loadScript(new URL(script.src, native.baseURI).href) === true; } catch (_) { loaded = false; }
          const handler = loaded ? script.onload : script.onerror;
          if (typeof handler === "function") handler();
        }, 0);
        return script;
      }
    }
  };

  const quiet = () => {};
  root.console = { log: quiet, debug: quiet, info: quiet, warn: quiet, error: quiet, trace: quiet };
  root.reportStage = index => {
    if (Number.isInteger(index) && index >= 1 && index <= 2) native.stage(index);
  };
  ["__avResolveURL", "__avFetch", "__avUTF8Encode", "__avUTF8Decode", "__avRandom", "__avNow",
   "__avSchedule", "__avCancel", "__avLoadScript", "__avStage", "__avBaseURI"].forEach(name => { try { delete root[name]; } catch (_) {} });
})(globalThis);
"""#
}
