import Foundation

/// Diagnostic context without request headers, query values, or credentials.
struct HTTPFailure: LocalizedError, Sendable {
    let status: Int
    let endpoint: String
    let detail: String?
    let retryAfter: String?

    init(response: HTTPURLResponse, data: Data, secret: String) {
        status = response.statusCode
        endpoint = response.url?.path ?? "Hermes API"
        retryAfter = response.value(forHTTPHeaderField: "Retry-After")
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let nested = json?["error"] as? [String: Any]
        let message = nested?["message"] as? String
            ?? json?["error"] as? String ?? json?["message"] as? String
            ?? json?["detail"] as? String
        let code = nested?["code"] as? String ?? json?["code"] as? String
        var text = [code, message].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ": ")
        if !secret.isEmpty { text = text.replacingOccurrences(of: secret, with: "[redacted]") }
        text = text.replacingOccurrences(of: #"(?i)(bearer\s+)[^\s\"']+"#, with: "$1[redacted]", options: .regularExpression)
        detail = text.isEmpty ? nil : String(text.prefix(1_000))
    }

    var errorDescription: String? {
        let action: String
        switch status {
        case 400, 422: action = "Hermes rejected the request. Check the selected model, profile, and supplied values."
        case 401: action = "The gateway rejected this connection's API key. Verify the key for the selected server."
        case 403: action = "This connection is not permitted to perform the operation. Check the gateway's profile permissions."
        case 404: action = "The resource or endpoint is unavailable. Refresh the view and verify that this gateway supports it."
        case 409: action = "The session or resource is busy or has changed. Refresh its state before retrying."
        case 413: action = "The attachment exceeds the gateway's request limit. Send a smaller file."
        case 429: action = "The gateway or model provider is rate limited. " + (retryAfter.map { "Retry after \($0)." } ?? "Wait before retrying.")
        case 502, 503, 504: action = "The gateway or its model provider is unavailable. Check the server and provider status before retrying."
        case 500...599: action = "Hermes could not complete the operation. Check the gateway log for this endpoint."
        default: action = "Hermes rejected this operation. Check the gateway log and endpoint compatibility."
        }
        return "\(endpoint) (HTTP \(status)): \(detail.map { $0 + ". " } ?? "")\(action)"
    }
}
