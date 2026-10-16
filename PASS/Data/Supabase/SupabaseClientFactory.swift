import Foundation
import Supabase

// MARK: - Client

/// Builds the single `SupabaseClient` the app uses. Auth tokens live in the Keychain (the SDK's default storage on iOS);
/// JSON is decoded with the RFC 3339 rules from the API contract (`backend/docs/01-API-CONTRACT.md`).
enum SupabaseClientFactory {
    static func make(url: URL, anonKey: String) -> SupabaseBackend {
        let decoder = makeDecoder()
        let encoder = makeEncoder()
        let options = SupabaseClientOptions(
            db: .init(schema: "public", encoder: encoder, decoder: decoder),
            auth: .init(),                                   // Keychain-backed `AuthLocalStorage` on Apple platforms
            global: .init(headers: ["x-pass-client": "ios"]))
        let client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey, options: options)
        return SupabaseBackend(client: client, decoder: decoder, encoder: encoder)
    }

    /// Dates: RFC 3339 with or without fractional seconds (Postgres emits up to six digits) and with `Z` or `±hh:mm`.
    nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = RFC3339.date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an RFC 3339 date: \(raw)")
            }
            return date
        }
        return decoder
    }

    nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(RFC3339.string(from: date))
        }
        return encoder
    }
}

/// Tolerant RFC 3339 parsing shared by the decoder and `ServerClock`.
enum RFC3339 {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated static func date(from raw: String) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tIndex = s.firstIndex(where: { $0 == "T" || $0 == " " }) else { return nil }
        if s[tIndex] == " " { s.replaceSubrange(tIndex...tIndex, with: "T") }
        // A `timestamp` without zone (e.g. `2026-10-10T12:00:00`) is UTC by contract.
        let timePart = s[s.index(after: tIndex)...]
        if !timePart.contains("Z") && !timePart.contains("+") && !timePart.contains("-") { s += "Z" }
        // ISO8601DateFormatter accepts at most three fractional digits; Postgres sends up to six.
        if let dot = s.firstIndex(of: "."), let end = s[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            let digits = String(s[s.index(after: dot)..<end])
            if digits.isEmpty {
                s.replaceSubrange(dot..<end, with: "")
            } else if digits.count != 3 {
                let normalized = String((digits + "000").prefix(3))
                s.replaceSubrange(dot..<end, with: "." + normalized)
            }
        }
        return fractional.date(from: s) ?? plain.date(from: s)
    }

    nonisolated static func string(from date: Date) -> String { fractional.string(from: date) }
}

// MARK: - Backend wrapper

/// Thin wrapper the repositories share: one client, one decoder, and the RPC/Edge Function plumbing with error mapping.
final class SupabaseBackend: @unchecked Sendable {
    let client: SupabaseClient
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    init(client: SupabaseClient, decoder: JSONDecoder, encoder: JSONEncoder) {
        self.client = client
        self.decoder = decoder
        self.encoder = encoder
    }

    /// The signed-in user's id from the locally cached session (no network).
    func currentUserID() throws -> UserID {
        guard let id = client.auth.currentUser?.id else { throw AppError.unauthorized }
        return UserID(id.uuidString.lowercased())
    }

    // MARK: RPC

    func rpc<T: Decodable>(_ name: String, _ params: RPCParams = [:]) async throws -> T {
        let data = try await rpcData(name, params)
        return try decode(T.self, from: data, context: name)
    }

    /// For functions that may return SQL `null` (e.g. `get_me` before onboarding).
    func rpcOptional<T: Decodable>(_ name: String, _ params: RPCParams = [:]) async throws -> T? {
        let data = try await rpcData(name, params)
        if Self.isNull(data) { return nil }
        return try decode(T.self, from: data, context: name)
    }

    func rpcVoid(_ name: String, _ params: RPCParams = [:]) async throws {
        _ = try await rpcData(name, params)
    }

    private func rpcData(_ name: String, _ params: RPCParams) async throws -> Data {
        do {
            let builder = try params.isEmpty ? client.rpc(name) : client.rpc(name, params: params)
            let response: PostgrestResponse<Void> = try await builder.execute()
            return response.data
        } catch {
            throw SupabaseErrorMapping.map(error)
        }
    }

    // MARK: Edge Functions

    func invoke<T: Decodable>(_ function: String, body: some Encodable & Sendable) async throws -> T {
        do {
            return try await client.functions.invoke(function, options: FunctionInvokeOptions(query: [], body: body, encoder: encoder), decoder: decoder)
        } catch {
            throw SupabaseErrorMapping.map(error)
        }
    }

    func invokeVoid(_ function: String, body: some Encodable & Sendable) async throws {
        do {
            try await client.functions.invoke(function, options: FunctionInvokeOptions(query: [], body: body, encoder: encoder))
        } catch {
            throw SupabaseErrorMapping.map(error)
        }
    }

    // MARK: Helpers

    func decode<T: Decodable>(_ type: T.Type, from data: Data, context: String) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("Decoding \(context) failed: \(error)")
            #endif
            throw AppError.unknown("Unexpected response from the server (\(context)).")
        }
    }

    private static func isNull(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return data.isEmpty }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "null"
    }
}

/// Request body shared by Edge Functions that take `{}`.
nonisolated struct EmptyBody: Encodable, Sendable {}

// MARK: - RPC parameters

/// Named RPC parameters. PostgREST matches a function by the full set of argument names, so `nil` must be sent as an
/// explicit JSON `null` (Swift's default encoding would drop the key).
nonisolated struct RPCParams: Encodable, Sendable, ExpressibleByDictionaryLiteral {
    enum Value: Encodable, Sendable {
        case string(String?)
        case int(Int?)
        case bool(Bool)
        case json(any Encodable & Sendable)

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let v): if let v { try c.encode(v) } else { try c.encodeNil() }
            case .int(let v): if let v { try c.encode(v) } else { try c.encodeNil() }
            case .bool(let v): try c.encode(v)
            case .json(let v): try v.encode(to: encoder)
            }
        }
    }

    private struct ParamKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    typealias Key = String
    let values: [String: Value]

    init(dictionaryLiteral elements: (String, Value)...) {
        values = Dictionary(elements, uniquingKeysWith: { _, last in last })
    }

    var isEmpty: Bool { values.isEmpty }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ParamKey.self)
        for (name, value) in values.sorted(by: { $0.key < $1.key }) {
            try container.encode(value, forKey: ParamKey(stringValue: name))
        }
    }
}
