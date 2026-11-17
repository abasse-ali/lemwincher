import Foundation

enum APIError: LocalizedError {
    case status(Int, String?)

    var errorDescription: String? {
        switch self {
        case .status(401, _), .status(403, _):
            return "Session expirée ou identifiants refusés. Reconnectez-vous à Open Prices dans Réglages."
        case .status(429, _):
            return "Trop de requêtes, réessayez dans un instant."
        case .status(let code, _) where code >= 500:
            return "Le service est momentanément indisponible (\(code))."
        case .status(let code, let detail):
            if let detail, !detail.isEmpty { return "Erreur \(code) : \(detail)" }
            return "Erreur du serveur (\(code))."
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.httpAdditionalHeaders = [
            "User-Agent": "Lemwincher/1.0 (iOS)",
            "Accept": "application/json",
        ]
        return URLSession(configuration: config)
    }()

    /// GET + décodage JSON. `snakeCase` convertit `product_name` en `productName`.
    static func get<T: Decodable>(_ urlString: String,
                                  query: [String: String] = [:],
                                  snakeCase: Bool = true) async throws -> T {
        guard var components = URLComponents(string: urlString) else { throw URLError(.badURL) }
        if !query.isEmpty {
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw URLError(.badURL) }
        return try await send(URLRequest(url: url), snakeCase: snakeCase)
    }

    static func send<T: Decodable>(_ request: URLRequest, snakeCase: Bool) async throws -> T {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.status(http.statusCode, errorDetail(from: data))
        }
        let decoder = JSONDecoder()
        if snakeCase {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
        }
        return try decoder.decode(T.self, from: data)
    }

    /// Message d'erreur lisible renvoyé par l'API ({"detail": "..."}).
    private static func errorDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let detail = object["detail"] as? String { return detail }
        if let first = object.first {
            return "\(first.key) : \(first.value)"
        }
        return nil
    }
}

/// Décode un élément de tableau sans faire échouer tout le tableau s'il est mal formé.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Lecture tolérante des champs JSON (un champ mal typé devient nil au lieu de tout faire échouer).
extension KeyedDecodingContainer {
    func lossyString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    func lossyDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    func lossyInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func lossyBool(_ key: Key) -> Bool? {
        try? decodeIfPresent(Bool.self, forKey: key)
    }
}
