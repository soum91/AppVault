import Foundation
@main struct StoreProtocolTests {
    static func main() throws {
        let origin = URL(string: "https://auth.itunes.apple.com/auth/v1/native/fast/")!
        let redirect = try StoreProtocol.redirect("/next", from: origin)
        precondition(redirect.absoluteString == "https://auth.itunes.apple.com/next")
        for invalid in ["http://buy.itunes.apple.com/a", "https://buy.itunes.apple.com.evil.invalid/a", "https://evil.invalid/", "https://user:pass@buy.itunes.apple.com/", "https://buy.itunes.apple.com:444/a", ""] {
            do { _ = try StoreProtocol.redirect(invalid, from: origin); fatalError("unsafe redirect accepted") } catch is StoreFailure { }
        }
        let body = try StoreProtocol.loginBody(email: "fixture@example.invalid", password: "a&<\"'", code: "123456", guid: "001122334455")
        let plist = try PropertyListSerialization.propertyList(from: body, options: [], format: nil) as! [String: String]
        precondition(plist["password"] == "a&<\"'123456" && plist["createSession"] == "true" && plist["attempt"] == "1")
        let headers = HTTPURLResponse(url: origin, statusCode: 200, httpVersion: nil, headerFields: ["x-set-apple-store-front":"143455-1,29", "pod":"25"])!
        let account = try StoreProtocol.loginResult(["passwordToken":"fixture-token", "dsPersonId":12345], response: headers, email: "fixture@example.invalid", suppliedCode: false)
        precondition(account.dsid == "12345" && account.storefront == "143455-1,29")
        let encoded = String(data: try JSONEncoder().encode(account), encoding: .utf8)!
        precondition(!encoded.contains("a&") && !encoded.contains("password"))
        do { _ = try StoreProtocol.dictionary(Data(), status: 403); fatalError("403 accepted") } catch let e as StoreFailure { precondition(e.code == "http_403") }
        do { _ = try StoreProtocol.loginResult(["customerMessage":"MZFinance.BadLogin.Configurator_message"], response: headers, email: "fixture@example.invalid", suppliedCode: false); fatalError("challenge accepted as login") } catch let e as StoreFailure { precondition(e.code == "two_factor") }
        for path in ["../bad", "/bad", "SC_Info/../../bad", "SC_Info//bad", "SC_Info\\bad"] { precondition(!StoreProtocol.safeRelativePath(path)) }
        precondition(StoreProtocol.safeRelativePath("SC_Info/App.sinf"))
        precondition(StoreProtocol.validCDNURL(URL(string:"https://iosapps.itunes.apple.com/file.ipa")!))
        precondition(!StoreProtocol.validCDNURL(URL(string:"https://itunes.apple.com.evil.invalid/file.ipa")!))
        print("Direct Store protocol fixtures passed: redirect boundaries, exact plist payload, header casing, token-only account, HTTP 403, 2FA, SINF paths, CDN hosts")
    }
}
