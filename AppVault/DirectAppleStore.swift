import Foundation
import ZIPFoundation
import ApplePackage

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
    private let guid: String
    private var authenticator: Authenticator?
    private var authenticationEmail: String?
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
    func signOut() { state = DirectStoreState(account: nil, cookies: []); authenticator = nil; authenticationEmail = nil }
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
    private func request(_ original: URL, body: Data? = nil, contentType: String = "application/x-apple-plist", account: StoreAccount? = nil) async throws -> (Data, HTTPURLResponse) {
        var url = original
        for _ in 0..<6 {
            try Task.checkCancellation()
            guard StoreProtocol.validStoreURL(url) else { throw StoreProtocol.failure("host_rejected", "Refused a non-Apple Store destination.") }
            var request = URLRequest(url: url)
            request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
            request.setValue(StoreProtocol.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.setValue("application/xml", forHTTPHeaderField: "Accept")
            request.setValue(cookieHeader(url), forHTTPHeaderField: "Cookie")
            if let account {
                request.setValue(account.dsid, forHTTPHeaderField: "X-Dsid")
                request.setValue(account.dsid, forHTTPHeaderField: "iCloud-Dsid")
                request.setValue(account.token, forHTTPHeaderField: "X-Token")
                request.setValue(account.storefront, forHTTPHeaderField: "X-Apple-Store-Front")
            }
            let (data, raw) = try await session.data(for: request)
            guard let response = raw as? HTTPURLResponse else { throw StoreProtocol.failure("non_http", "Apple returned a non-HTTP response.") }
            retainCookies(response, url: url)
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
    func login(email: String, password: String, code: String) async throws {
        // ApplePackage implements fresh native SAP setup and signs the exact
        // outgoing login body. Keep its actor alive across a 2FA continuation.
        Configuration.deviceIdentifier = guid
        APLogger.verbose = false
        var logger = APLogger.logger
        logger.logLevel = .critical
        APLogger.logger = logger
        do {
            if code.isEmpty || authenticator == nil || authenticationEmail != email {
                let cookies = state.cookies.map { cookie in
                    ApplePackage.Cookie(name: cookie.name, value: cookie.value, path: cookie.path, domain: cookie.domain,
                        expiresAt: cookie.expires?.timeIntervalSince1970, httpOnly: true, secure: cookie.secure)
                }
                authenticator = try await Authenticator(cookies: cookies)
                authenticationEmail = email
            }
            guard let authenticator else { throw StoreProtocol.failure("auth_session_missing", "Start sign-in again to establish a fresh authentication session.") }
            try Task.checkCancellation()
            var result = try await authenticator.authenticate(email: email, password: password, code: code)
            // Never serialize ApplePackage.Account, which includes a password.
            // Convert to AppVault's token-only state before any persistence.
            result.password = ""
            guard !result.passwordToken.isEmpty, !result.directoryServicesIdentifier.isEmpty else {
                throw StoreProtocol.failure("invalid_signed_session", "Apple returned an incomplete signed-in session.")
            }
            state.account = StoreAccount(email: result.email, token: result.passwordToken, dsid: result.directoryServicesIdentifier,
                storefront: result.store, pod: result.pod)
            state.cookies = result.cookie.map { StoreCookie(name: $0.name, value: $0.value, domain: $0.domain ?? "buy.itunes.apple.com",
                path: $0.path, secure: $0.secure, expires: $0.expiresAt.map(Date.init(timeIntervalSince1970:))) }
            self.authenticator = nil; authenticationEmail = nil
        } catch AuthenticationError.verificationCodeRequired {
            throw StoreProtocol.failure("two_factor", "Apple requested a verification code or rejected the credentials. If a code appeared on your trusted device, enter it below; otherwise check the email and password. A code prompt alone does not prove Apple sent one.")
        } catch let failure as StoreFailure { throw failure
        } catch {
            // Match only known status/error classes; never expose a raw server
            // body, account object, SAP state, signature, password or token.
            let description = error.localizedDescription.lowercased()
            if description.contains("403") {
                throw StoreProtocol.failure("signed_auth_http_403", "Apple rejected the SAP-signed sign-in request (HTTP 403). This is no longer the unsigned login path. Open Settings > Backend Report for the installed version and error code.")
            }
            if description.contains("verification") || description.contains("5005") {
                throw StoreProtocol.failure("verification_rejected", "Apple rejected the verification code. Request a current code on your trusted device and try again.")
            }
            if error is SAPError {
                self.authenticator = nil; authenticationEmail = nil
                throw StoreProtocol.failure("sap_setup_failed", "Native Apple request signing could not establish a fresh session. Check the connection and try signing in again.")
            }
            let issue = error as NSError
            throw StoreProtocol.failure("auth_\(issue.code)", "Apple sign-in did not complete. Check account status, credentials and the network connection. No successful login is claimed.")
        }
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
        let pod = account.pod.flatMap { Int($0) }.map { "p\($0)-buy.itunes.apple.com" } ?? "buy.itunes.apple.com"
        let url = URL(string: "https://\(pod)/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=\(guid)")!
        var payload: [String: Any] = ["creditDisplay":"", "guid":guid, "salableAdamId":String(app.trackId)]
        if !versionID.isEmpty {
            guard versionID.allSatisfy(\.isNumber) else { throw StoreProtocol.failure("invalid_version", "The external version identifier must contain digits only.") }
            payload["externalVersionId"] = versionID
        }
        let (data, response) = try await request(url, body: StoreProtocol.plist(payload), account: account)
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
