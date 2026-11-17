import Foundation

// Ephemeral Apple-issued context. Never serialized to account storage/reports.
struct AppleVerificationSession {
    var sessionID: String
    var scnt: String
    var widgetKey: String?
    var clientID: String?
    static func from(_ response: HTTPURLResponse) -> Self? {
        guard let id = response.value(forHTTPHeaderField: "X-Apple-ID-Session-Id"), !id.isEmpty,
              let nonce = response.value(forHTTPHeaderField: "scnt"), !nonce.isEmpty else { return nil }
        return Self(sessionID: id, scnt: nonce,
            widgetKey: response.value(forHTTPHeaderField: "X-Apple-Widget-Key"),
            clientID: response.value(forHTTPHeaderField: "X-Apple-OAuth-Client-Id"))
    }
    mutating func update(_ response: HTTPURLResponse) {
        if let value = response.value(forHTTPHeaderField: "X-Apple-ID-Session-Id"), !value.isEmpty { sessionID = value }
        if let value = response.value(forHTTPHeaderField: "scnt"), !value.isEmpty { scnt = value }
    }
    func request(code: String? = nil) throws -> URLRequest {
        let path = code == nil ? "/verify/trusteddevice" : "/verify/trusteddevice/securitycode"
        var request = URLRequest(url: URL(string: "https://idmsa.apple.com/appleauth/auth" + path)!)
        request.httpMethod = code == nil ? "PUT" : "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(StoreProtocol.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(sessionID, forHTTPHeaderField: "X-Apple-ID-Session-Id")
        request.setValue(scnt, forHTTPHeaderField: "scnt")
        request.setValue("https://idmsa.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://idmsa.apple.com/", forHTTPHeaderField: "Referer")
        if let widgetKey { request.setValue(widgetKey, forHTTPHeaderField: "X-Apple-Widget-Key") }
        if let clientID { request.setValue(clientID, forHTTPHeaderField: "X-Apple-OAuth-Client-Id") }
        if let code {
            guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                throw StoreProtocol.failure("invalid_code", "Enter the six-digit code shown on your trusted device.")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["securityCode": ["code": code]])
        }
        return request
    }
    static func isChallengeResponse(_ fields: [String: Any], response: HTTPURLResponse) -> Bool {
        guard from(response) != nil, fields["passwordToken"] == nil else { return false }
        if challenge(fields) { return true }
        let failure = String(describing: fields["failureType"] ?? "")
        let errors = fields["serviceErrors"] as? [Any] ?? []
        return failure.isEmpty && errors.isEmpty && [401, 406, 409].contains(response.statusCode)
    }
    static func challenge(_ fields: [String: Any]) -> Bool {
        let nested = fields["authentication"] as? [String: Any] ?? fields["auth"] as? [String: Any] ?? fields
        let type = (nested["authType"] as? String ?? "").lowercased()
        return ["hsa2", "secondaryauth", "twostep"].contains(type) ||
            nested["trustedPhoneNumbers"] != nil || nested["trustedDevices"] != nil || (nested["m-allowed"] as? Bool) == true
    }
}
