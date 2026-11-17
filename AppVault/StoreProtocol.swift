import Foundation

struct StoreApp: Codable, Identifiable {
    let trackId: Int64
    let bundleId: String?
    let trackName: String?
    let version: String?
    let price: Double?
    var id: Int64 { trackId }
}
struct StoreAccount: Codable {
    let email: String
    let token: String
    let dsid: String
    let storefront: String
    let pod: String?
}
struct StoreFailure: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { "\(message) [\(code)]" }
}
enum StoreProtocol {
    static let userAgent = "Configurator/2.21 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6"
    static func failure(_ code: String, _ message: String) -> StoreFailure { StoreFailure(code: code, message: message) }
    static func validStoreURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return host == "itunes.apple.com" || host.hasSuffix(".itunes.apple.com") || host == "auth.tv.apple.com"
    }
    static func validCDNURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return ["apple.com", "cdn-apple.com", "itunes.apple.com", "mzstatic.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func redirect(_ value: String?, from: URL) throws -> URL {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: value, relativeTo: from)?.absoluteURL, validStoreURL(url) else {
            throw failure("redirect_rejected", "Apple returned a missing or unsafe redirect destination. Credentials were not forwarded.")
        }
        return url
    }
    static func loginBody(email: String, password: String, code: String, guid: String) throws -> Data {
        let body = ["appleId": email, "attempt": code.isEmpty ? "1" : "2", "guid": guid, "password": password + code, "rmp": "0", "why": "signIn"]
        return try plist(body)
    }
    static func plist(_ value: Any) throws -> Data { try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0) }
    static func dictionary(_ data: Data, status: Int) throws -> [String: Any] {
        if status == 403 { throw failure("http_403", "Apple rejected this Store request (HTTP 403). Open Settings > Backend Report for the installed version and failure code.") }
        if status == 429 { throw failure("http_429", "Apple rate-limited the request. Wait before trying again.") }
        guard (200..<300).contains(status) else { throw failure("http_\(status)", "Apple returned HTTP \(status).") }
        if let parsed = try? ApplePropertyList.dictionary(data) { return parsed }
        if let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] { return value }
        if let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return value }
        // Some bag replies wrap an XML plist in a short preamble.
        if let xml = String(data: data, encoding: .utf8), let start = xml.range(of: "<plist"), let end = xml.range(of: "</plist>", range: start.lowerBound..<xml.endIndex), let body = xml[start.lowerBound..<end.upperBound].data(using: .utf8), let value = try? PropertyListSerialization.propertyList(from: body, options: [], format: nil) as? [String: Any] { return value }
        throw failure("invalid_response", "Apple returned an empty or unsupported response. No account or backup was saved.")
    }
    static func loginResult(_ dict: [String: Any], response: HTTPURLResponse, email: String, suppliedCode: Bool) throws -> StoreAccount {
        let message = dict["customerMessage"] as? String ?? ""
        let code = String(describing: dict["failureType"] ?? "")
        if !suppliedCode && (message == "MZFinance.BadLogin.Configurator_message" || (dict["m-allowed"] as? Bool) == true) {
            throw failure("two_factor", "Apple requires a verification code. Enter the six-digit code from your trusted device and submit again. The Configurator response can also mean incorrect credentials.")
        }
        guard let token = dict["passwordToken"] as? String, !token.isEmpty,
              let rawID = dict["dsPersonId"], !(String(describing: rawID)).isEmpty else {
            // Do not put raw server bodies, account identifiers or passwords into reports.
            let known: [String: String] = ["Your account is disabled.": "Apple reported that this account is disabled.", "Your password has changed.": "Apple reported expired credentials. Sign in again."]
            throw failure(code.allSatisfy(\.isNumber) && !code.isEmpty ? "apple_" + code : "login_rejected", known[message] ?? "Apple did not issue an App Store session. Check the credentials or account status. This build does not bypass Apple's authentication requirements.")
        }
        let storefront = response.value(forHTTPHeaderField: "X-Set-Apple-Store-Front") ?? response.value(forHTTPHeaderField: "X-Apple-Store-Front") ?? ""
        guard !storefront.isEmpty else { throw failure("missing_storefront", "Apple issued an incomplete session with no storefront.") }
        let pod = response.value(forHTTPHeaderField: "pod")
        return StoreAccount(email: email, token: token, dsid: String(describing: rawID), storefront: storefront, pod: pod)
    }
    static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0.isEmpty }
    }
}
