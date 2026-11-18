import Foundation
import ZIPFoundation

struct StoreCookie: Codable {
    let name: String; let value: String; let domain: String; let path: String; let secure: Bool; let expires: Date?
    init(name: String, value: String, domain: String, path: String, secure: Bool, expires: Date?) {
        self.name = name; self.value = value; self.domain = domain; self.path = path; self.secure = secure; self.expires = expires
    }
    init(_ cookie: HTTPCookie) { name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path; secure = cookie.isSecure; expires = cookie.expiresDate }
    var cookie: HTTPCookie? {
        var values: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path, .secure: secure ? "TRUE" : "FALSE"]
        if let expires { values[.expires] = expires }
        return HTTPCookie(properties: values)
    }
}
struct DirectStoreState: Codable { var account: StoreAccount?; var cookies: [StoreCookie] }
private final class NoAutomaticRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
private final class CDNDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(StoreProtocol.validCDNURL) == true ? request : nil)
    }
}
actor DirectAppleStore {
    private var state: DirectStoreState
    private var verification: AppleVerificationSession?
    private var verificationEmail: String?
    private var trace: [String] = []
    func diagnostics() -> String { trace.joined(separator: "\n") }
    func verificationAvailable() -> Bool { verification != nil }
    func clearVerification() { verification = nil; verificationEmail = nil }
    private func record(_ response: HTTPURLResponse, data: Data, stage: String) {
        let fields = StoreProtocol.responseFields(data)
        let failure = String(describing: fields?["failureType"] ?? "")
        let numeric = !failure.isEmpty && failure.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") }) ? failure : "none"
        trace.append("stage=\(stage); http=\(response.statusCode); bytes=\(data.count); structured=\(fields != nil); verification_session=\(AppleVerificationSession.from(response) != nil); challenge=\(fields.map(AppleVerificationSession.challenge) ?? false); failure=\(numeric)")
        if trace.count > 30 { trace.removeFirst(trace.count - 30) }
    }
    private var routingStorefront: String?
    private var routingPod: String?
    private let guid: String
    private let session: URLSession
    private let cdn: URLSession
    init(guid: String, state: DirectStoreState?) {
        self.guid = guid.replacingOccurrences(of: ":", with: "").uppercased()
        self.state = state ?? DirectStoreState(account: nil, cookies: [])
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config, delegate: NoAutomaticRedirects(), delegateQueue: nil)
        let downloadConfig = URLSessionConfiguration.ephemeral
        downloadConfig.httpCookieStorage = nil; downloadConfig.httpShouldSetCookies = false; downloadConfig.urlCache = nil
        downloadConfig.timeoutIntervalForRequest = 60; downloadConfig.timeoutIntervalForResource = 3600
        cdn = URLSession(configuration: downloadConfig, delegate: CDNDelegate(), delegateQueue: nil)
    }
    func snapshot() -> DirectStoreState { state }
    func signOut() { state = DirectStoreState(account: nil, cookies: []); clearVerification() }
    private func cookieHeader(_ url: URL) -> String {
        let cookies = state.cookies.compactMap(\.cookie).filter { c in
            let domain = c.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let host = url.host?.lowercased() ?? ""
            let path = url.path.isEmpty ? "/" : url.path
            let pathMatch = path == c.path || (path.hasPrefix(c.path) && (c.path.hasSuffix("/") || path.dropFirst(c.path.count).hasPrefix("/")))
            return (host == domain || (c.domain.hasPrefix(".") && host.hasSuffix("." + domain))) && pathMatch && (!c.isSecure || url.scheme == "https") && (c.expiresDate == nil || c.expiresDate! > Date())
        }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? ""
    }
    private func retainCookies(_ response: HTTPURLResponse, url: URL) {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) }
        for c in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            let domain = c.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let host = url.host?.lowercased() ?? ""
            guard domain.contains("."), host == domain || host.hasSuffix("." + domain) else { continue }
            state.cookies.removeAll { $0.name == c.name && $0.domain == c.domain && $0.path == c.path }
            if c.expiresDate == nil || c.expiresDate! > Date() { state.cookies.append(StoreCookie(c)) }
        }
    }
    private func request(_ original: URL, body: Data? = nil, contentType: String = "application/x-apple-plist", account: StoreAccount? = nil, extraHeaders: ((URL) async throws -> [String: String])? = nil) async throws -> (Data, HTTPURLResponse) {
        var url = original
        for _ in 0..<6 {
            try Task.checkCancellation()
            guard StoreProtocol.validStoreURL(url) else { throw StoreProtocol.failure("host_rejected", "Refused a non-Apple Store destination.") }
            var request = URLRequest(url: url)
            request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
            request.setValue(StoreProtocol.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue(cookieHeader(url), forHTTPHeaderField: "Cookie")
            if let account {
                request.setValue(account.dsid, forHTTPHeaderField: "X-Dsid")
                request.setValue(account.dsid, forHTTPHeaderField: "iCloud-Dsid")
                request.setValue(account.token, forHTTPHeaderField: "X-Token")
                request.setValue(account.storefront, forHTTPHeaderField: "X-Apple-Store-Front")
            }
            if let extraHeaders { for (name, value) in try await extraHeaders(url) { request.setValue(value, forHTTPHeaderField: name) } }
            let (data, raw) = try await session.data(for: request)
            guard let response = raw as? HTTPURLResponse else { throw StoreProtocol.failure("non_http", "Apple returned a non-HTTP response.") }
            record(response, data: data, stage: url.path.contains("bag.xml") ? "bag" : url.host == "auth.itunes.apple.com" ? "sign_in" : "store")
            retainCookies(response, url: url)
            if let storefront = response.value(forHTTPHeaderField: "X-Set-Apple-Store-Front") ?? response.value(forHTTPHeaderField: "X-Apple-Store-Front"), !storefront.isEmpty { routingStorefront = storefront }
            if let pod = response.value(forHTTPHeaderField: "pod"), !pod.isEmpty { routingPod = pod }
            if [301,302,303,307,308].contains(response.statusCode) {
                // Use Foundation's case-insensitive header lookup. Keep the POST
                // body intact while resolving only validated Apple destinations.
                url = try StoreProtocol.redirect(response.value(forHTTPHeaderField: "Location"), from: url)
                continue
            }
            return (data, response)
        }
        throw StoreProtocol.failure("redirect_limit", "Apple exceeded the five-redirect limit.")
    }
    private func attested(_ url: URL, body: Data, account: StoreAccount? = nil, signature: String? = nil) async throws -> (Data, HTTPURLResponse) {
        let signer = await LocalSAPSigner.shared
        var didReset = false, didProvision = false
        for _ in 0..<3 {
            try Task.checkCancellation()
            let (data, response) = try await request(url, body: body, account: account, extraHeaders: { _ in
                var headers = try await signer.storeProofHeaders(guid: self.guid, useCache: true) ?? [:]
                if let signature { headers["X-Apple-ActionSignature"] = signature }
                return headers
            })
            let fields = StoreProtocol.responseFields(data) ?? [:]
            let action = (response.value(forHTTPHeaderField: "X-Apple-AMD-Action") ??
                (fields["customerMessage"] as? String)?.split(separator: ":").last.map(String.init) ?? "").uppercased()
            if action == "RP", !didReset {
                try await signer.resetStoreProof(guid: guid); didReset = true; continue
            }
            if action == "SP", !didProvision {
                guard let challenge = response.value(forHTTPHeaderField: "X-Apple-AMD-Data"), challenge.count <= 16384,
                      let bytes = Data(base64Encoded: challenge), !bytes.isEmpty, bytes.base64EncodedString() == challenge else {
                    throw StoreProtocol.failure("invalid_store_challenge", "Apple returned an invalid device-attestation challenge.")
                }
                _ = try await signer.provisionStoreProof(challenge: challenge, guid: guid, useCache: true)
                didProvision = true; continue
            }
            if action == "SP" || action == "RP" { throw StoreProtocol.failure("store_proof_rejected", "Apple rejected the Store device proof after provisioning.") }
            return (data, response)
        }
        throw StoreProtocol.failure("store_proof_limit", "Store device verification exceeded its retry limit.")
    }
    func requestTrustedDeviceApproval() async throws {
        guard let context = verification else { throw StoreProtocol.failure("no_verification_session", "Apple did not provide a trusted-device approval session. Start sign-in again or use a verification code from your Apple Account settings.") }
        _ = try await verificationRequest(context.request(), stage: "trusted_device_prompt")
    }
    private func verificationRequest(_ original: URLRequest, stage: String) async throws -> (Data, HTTPURLResponse) {
        var request = original
        guard request.url?.host == "idmsa.apple.com", request.url?.scheme == "https" else { throw StoreProtocol.failure("verification_origin", "Refused an unexpected verification destination.") }
        request.setValue(cookieHeader(request.url!), forHTTPHeaderField: "Cookie")
        let (data, raw) = try await session.data(for: request)
        guard let response = raw as? HTTPURLResponse else { throw StoreProtocol.failure("verification_transport", "Apple returned no verification response.") }
        record(response, data: data, stage: stage)
        retainCookies(response, url: request.url!)
        verification?.update(response)
        guard (200..<300).contains(response.statusCode) else {
            throw StoreProtocol.failure("verification_http_\(response.statusCode)", stage == "trusted_device_prompt" ? "Apple did not accept the trusted-device notification request. Try again or use a code from your Apple Account settings." : "Apple did not accept this verification code. Enter a current code or restart sign-in.")
        }
        return (data, response)
    }
    func login(email: String, password: String, code: String, progress: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        guard code.isEmpty || (code.count == 6 && code.allSatisfy({ $0.isASCII && $0.isNumber })) else {
            throw StoreProtocol.failure("invalid_code", "Enter a six-digit verification code.")
        }
        if code.isEmpty { routingStorefront = nil; routingPod = nil; clearVerification() }
        if let owner = verificationEmail, owner != email { clearVerification() }
        var sessionVerified = false
        if !code.isEmpty, let context = verification, verificationEmail == email {
            _ = try await verificationRequest(context.request(code: code), stage: "trusted_device_code")
            sessionVerified = true
        }
        progress("Contacting Apple Store authentication")
        let (bagData, bagResponse) = try await request(URL(string: "https://init.itunes.apple.com/bag.xml?guid=\(guid)&ix=6")!)
        let bag = try StoreProtocol.dictionary(bagData, status: bagResponse.statusCode)
        let urls = bag["urlBag"] as? [String: Any] ?? bag
        guard let text = (bag["authenticateAccount"] ?? urls["authenticateAccount"]) as? String,
              let endpoint = URL(string: text), StoreProtocol.validStoreURL(endpoint) else {
            throw StoreProtocol.failure("bag_endpoint", "Apple did not advertise a valid HTTPS authentication endpoint.")
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        // Keep the native path exactly as advertised; forcing /fast breaks AMD.
        var items = components.queryItems ?? []; items.removeAll { $0.name == "guid" }; items.append(URLQueryItem(name: "guid", value: guid)); components.queryItems = items
        let body = try StoreProtocol.loginBody(email: email, password: password, code: sessionVerified ? "" : code, guid: guid)
        let signer = await LocalSAPSigner.shared
        progress("Preparing signed Apple request")
        let signature = try await signer.sign(body, guid: guid, useCache: true, cacheSignature: false, progress: progress)
        progress("Requesting Apple Store session")
        let (data, response) = try await attested(components.url!, body: body, signature: signature)
        progress("Processing Apple Store response")
        let challengeFields = StoreProtocol.responseFields(data) ?? [:]
        if AppleVerificationSession.isChallengeResponse(challengeFields, response: response), let context = AppleVerificationSession.from(response) {
            verification = context; verificationEmail = email
            do {
                try await requestTrustedDeviceApproval()
                throw StoreProtocol.failure("two_factor", "Approval requested. Check your trusted Apple devices, tap Allow if prompted, and enter the verification code below.")
            } catch let failure as StoreFailure where failure.code == "two_factor" { throw failure
            } catch {
                throw StoreProtocol.failure("two_factor", "Apple opened a verification session, but the notification request did not complete. Use Request Approval to retry, or enter a current trusted-device code.")
            }
        }
        if AppleVerificationSession.challenge(challengeFields), challengeFields["passwordToken"] == nil {
            throw StoreProtocol.failure("two_factor", "Apple requires a verification code but did not return a session for requesting a device prompt. Enter a current code from a trusted device.")
        }
        let fields = try StoreProtocol.dictionary(data, status: response.statusCode)
        state.account = try StoreProtocol.loginResult(fields, response: response, email: email, suppliedCode: !code.isEmpty, fallbackStorefront: routingStorefront, fallbackPod: routingPod)
        clearVerification()
    }
    func search(_ term: String) async throws -> [StoreApp] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        // Match the account's storefront when it is in the public Apple list.
        let country = countryCode()
        components.queryItems = [URLQueryItem(name: "term", value: term), URLQueryItem(name: "country", value: country), URLQueryItem(name: "entity", value: "software"), URLQueryItem(name: "limit", value: "30")]
        let (data, response) = try await request(components.url!)
        guard response.statusCode == 200 else { throw StoreProtocol.failure("search_http_\(response.statusCode)", "App Store search failed.") }
        struct Results: Decodable { let results: [StoreApp] }
        return try JSONDecoder().decode(Results.self, from: data).results
    }
    private func countryCode() -> String {
        let sf = state.account?.storefront.components(separatedBy: "-").first ?? ""
        return ["143441":"US", "143455":"CA", "143444":"GB", "143443":"DE", "143442":"FR", "143462":"JP", "143465":"CN", "143460":"AU", "143467":"IN", "143464":"SG", "143470":"TW", "143463":"HK", "143466":"KR" ][sf] ?? (Locale.current.region?.identifier ?? "US")
    }
    func download(_ app: StoreApp, directory: URL, versionID: String, progress: @escaping @Sendable (String) -> Void) async throws -> URL {
        guard let account = state.account else { throw StoreProtocol.failure("sign_in_required", "Sign in to your Apple Account first.") }
        progress("Requesting the IPA from Apple")
        let url = URL(string: "https://downloaddispatch.itunes.apple.com/WebObjects/DownloadDispatch.woa/wa/ent/download?guid=\(guid)")!
        let signer = await LocalSAPSigner.shared
        let sync = try await signer.kbsync(guid: guid, dsid: account.dsid, useCache: true)
        var payload: [String: Any] = ["creditDisplay":"", "guid":guid, "salableAdamId":NSNumber(value: app.trackId), "serialNumber":"0", "kbsync":sync]
        if !versionID.isEmpty {
            guard versionID.allSatisfy(\.isNumber) else { throw StoreProtocol.failure("invalid_version", "The external version identifier must contain digits only.") }
            payload["externalVersionId"] = versionID
        }
        let (data, response) = try await attested(url, body: StoreProtocol.plist(payload), account: account)
        let dict = try StoreProtocol.dictionary(data, status: response.statusCode)
        if let failure = dict["failureType"], !String(describing: failure).isEmpty {
            let value = String(describing: failure)
            let message = value == "9610" ? "This account does not own this app. Obtain its license in the App Store first." : "Apple rejected the IPA request. Sign in again if your session has expired."
            throw StoreProtocol.failure(value.allSatisfy(\.isNumber) ? "apple_" + value : "download_rejected", message)
        }
        guard let song = (dict["songList"] as? [[String: Any]])?.first, let rawURL = song["URL"] as? String, let downloadURL = URL(string: rawURL), StoreProtocol.validCDNURL(downloadURL), let metadata = song["metadata"] as? [String: Any] else { throw StoreProtocol.failure("missing_package", "Apple returned no usable IPA package.") }
        progress("Downloading IPA from Apple's CDN")
        var req = URLRequest(url: downloadURL); req.setValue(StoreProtocol.userAgent, forHTTPHeaderField: "User-Agent"); req.setValue("buy", forHTTPHeaderField: "Apple-Download-Type")
        // This separate session has no account cookies, token, or DSID headers.
        let (temporary, rawResponse) = try await cdn.download(for: req)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let reply = rawResponse as? HTTPURLResponse, reply.statusCode == 200 else { throw StoreProtocol.failure("cdn_rejected", "Apple's CDN did not return a complete IPA.") }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appendingPathComponent(UUID().uuidString + ".partial")
        try FileManager.default.moveItem(at: temporary, to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }
        progress("Validating package and adding Apple license metadata")
        try Self.finishPackage(staged, expectedBundle: app.bundleId, metadata: metadata, sinfs: song["sinfs"] as? [[String: Any]] ?? [], email: account.email)
        try Task.checkCancellation()
        let destination = directory.appendingPathComponent("\(app.trackId)-\(UUID().uuidString.prefix(8)).ipa")
        try FileManager.default.moveItem(at: staged, to: destination)
        return destination
    }
    private static func finishPackage(_ url: URL, expectedBundle: String?, metadata: [String: Any], sinfs: [[String: Any]], email: String) throws {
        let archive = try Archive(url: url, accessMode: .update)
        guard let info = archive.first(where: { $0.path.hasPrefix("Payload/") && $0.path.split(separator: "/").count == 3 && $0.path.hasSuffix(".app/Info.plist") }) else { throw StoreProtocol.failure("invalid_ipa", "The downloaded package has no main iOS application bundle.") }
        func read(_ entry: Entry) throws -> Data {
            guard entry.uncompressedSize <= 4 * 1024 * 1024 else { throw StoreProtocol.failure("oversized_metadata", "Package metadata exceeded the supported size.") }
            var data = Data(); _ = try archive.extract(entry) { data.append($0) }; return data
        }
        guard let plist = try PropertyListSerialization.propertyList(from: read(info), options: [], format: nil) as? [String: Any], let executable = plist["CFBundleExecutable"] as? String, StoreProtocol.safeRelativePath(executable), !executable.contains("/") else { throw StoreProtocol.failure("invalid_info", "The IPA has invalid bundle metadata.") }
        if let expectedBundle, plist["CFBundleIdentifier"] as? String != expectedBundle { throw StoreProtocol.failure("bundle_mismatch", "The package does not match the requested app.") }
        let root = String(info.path.dropLast("Info.plist".count))
        func write(_ data: Data, path: String) throws {
            if let old = archive[path] { try archive.remove(old) }
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<min(data.count, Int(position) + size))
            }
        }
        var manifestPaths: [String] = []
        if let manifest = archive[root + "SC_Info/Manifest.plist"], let dict = try PropertyListSerialization.propertyList(from: read(manifest), options: [], format: nil) as? [String: Any] { manifestPaths = dict["SinfPaths"] as? [String] ?? [] }
        if !sinfs.isEmpty {
            guard manifestPaths.isEmpty ? sinfs.count == 1 : manifestPaths.count == sinfs.count else { throw StoreProtocol.failure("sinf_mapping", "Apple's license data does not match the IPA manifest.") }
            for (index, sinf) in sinfs.enumerated() {
                let path = manifestPaths.isEmpty ? "SC_Info/\(executable).sinf" : manifestPaths[index]
                guard StoreProtocol.safeRelativePath(path), let bytes = (sinf["sinf"] as? Data) ?? (sinf["sinf"] as? String).flatMap({ Data(base64Encoded: $0) }) else { throw StoreProtocol.failure("invalid_sinf", "Apple returned an invalid license entry.") }
                try write(bytes, path: root + path)
            }
        }
        var clean = metadata
        clean.removeValue(forKey: "passwordToken"); clean.removeValue(forKey: "password")
        clean["apple-id"] = email; clean["userName"] = email
        try write(StoreProtocol.plist(clean), path: "iTunesMetadata.plist")
    }
}
