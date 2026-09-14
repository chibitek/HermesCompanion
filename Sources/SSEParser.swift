import Foundation

/// Foundation's AsyncLineSequence may omit empty lines. SSE needs those lines
/// to dispatch frames before the socket closes, so decode delimiters ourselves.
struct SSELineDecoder {
    private var buffer = Data()
    private var wasCR = false

    mutating func consume(_ byte: UInt8) throws -> String? {
        if byte == 10, wasCR { wasCR = false; return nil }
        wasCR = byte == 13
        if byte == 10 || byte == 13 {
            return try finish()
        }
        guard buffer.count < 16_777_216 else {
            throw APIError.sseParseError("A stream line exceeded the 16 MB safety limit.")
        }
        buffer.append(byte)
        return nil
    }

    mutating func finish() throws -> String {
        defer { buffer.removeAll(keepingCapacity: true) }
        guard let line = String(data: buffer, encoding: .utf8) else {
            throw APIError.sseParseError("The gateway sent invalid UTF-8 in its stream.")
        }
        return line
    }
}

/// Parses event boundaries independently of network packet boundaries.
struct SSEParser {
    private var name = ""
    private var lines: [String] = []

    mutating func consume(_ raw: String) throws -> SSEEventPayload? {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        if line.isEmpty { return try finish() }
        if line.hasPrefix("event:") { name = value(line, prefix: "event:") }
        if line.hasPrefix("data:") { lines.append(value(line, prefix: "data:")) }
        return nil
    }

    mutating func finish() throws -> SSEEventPayload? {
        defer { name = ""; lines = [] }
        guard !lines.isEmpty else { return nil }
        let text = lines.joined(separator: "\n")
        if text == "[DONE]" {
            return SSEEventPayload(event: "done", sessionId: nil, runId: nil, message_id: nil,
                                   delta: nil, content: nil, toolName: nil, preview: nil,
                                   args: nil, completed: nil, partial: nil, interrupted: nil, message: nil)
        }
        do {
            var event = try JSONDecoder().decode(SSEEventPayload.self, from: Data(text.utf8))
            if !name.isEmpty { event.event = name }
            guard !event.event.isEmpty else {
                throw APIError.sseParseError("The gateway omitted the event type. Check its streaming API version.")
            }
            return event
        } catch let failure as APIError {
            throw failure
        } catch {
            let json = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
            if name == "error", let message = json as? String {
                return SSEEventPayload(event: "error", sessionId: nil, runId: nil, message_id: nil,
                                       delta: nil, content: nil, toolName: nil, preview: nil,
                                       args: nil, completed: nil, partial: nil, interrupted: nil, message: message)
            }
            if name == "error", json == nil, !text.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
                return SSEEventPayload(event: "error", sessionId: nil, runId: nil, message_id: nil,
                                       delta: nil, content: nil, toolName: nil, preview: nil,
                                       args: nil, completed: nil, partial: nil, interrupted: nil, message: text)
            }
            let field = Self.decodingFailure(error)
            // Only known protocol names and schema fields enter diagnostics. Never
            // log the raw JSON, decoder debugDescription, or server-provided values.
            let jsonName = (json as? [String: Any])?["event"] as? String
            let candidate = name.isEmpty ? jsonName ?? "" : name
            let label = Self.knownEvents.contains(candidate) ? candidate : "unrecognized"
            let detail = "The gateway sent an invalid \(label) frame. \(field) Check the gateway log and streaming API compatibility."
            #if DEBUG
            FileLogger.shared.log("SSEParser: \(detail)")
            #endif
            throw APIError.sseParseError(detail)
        }
    }

    private static let knownEvents: Set<String> = [
        "assistant.delta", "assistant.completed", "message.started", "message.delta", "message.completed",
        "run.started", "run.progress", "run.completed", "run.failed", "run.cancelled", "run.interrupted",
        "tool.started", "tool.progress", "tool.completed", "tool.failed", "error", "done", "workspace.changed"
    ]

    private static func decodingFailure(_ error: Error) -> String {
        let path: [CodingKey]
        let reason: String
        switch error {
        case DecodingError.typeMismatch(_, let context):
            path = context.codingPath
            reason = "has an unexpected JSON type"
        case DecodingError.valueNotFound(_, let context):
            path = context.codingPath
            reason = "requires a non-null value"
        case DecodingError.keyNotFound(let key, let context):
            path = context.codingPath + [key]
            reason = "is required but missing"
        default:
            return "The payload is not valid JSON or contains an unsupported field value."
        }
        let fields: Set<String> = ["event", "session_id", "run_id", "message_id", "delta", "content",
            "tool_name", "preview", "args", "completed", "partial", "interrupted", "message", "runtime",
            "sequence", "code", "id", "role", "provider", "model", "route_source", "model_lock", "requested"]
        let field = path.map { fields.contains($0.stringValue) ? $0.stringValue : "field" }.joined(separator: ".")
        return "Field '\(field.isEmpty ? "payload" : field)' \(reason)."
    }

    private func value(_ line: String, prefix: String) -> String {
        let text = String(line.dropFirst(prefix.count))
        return text.hasPrefix(" ") ? String(text.dropFirst()) : text
    }
}
