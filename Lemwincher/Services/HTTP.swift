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
        // Journal : adresse sans ses paramètres (ni position ni recherche).
        let place = Log.describe(request.url)
        let started = Date()
        let host = request.url?.host ?? "Serveur"
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            if !error.isCancellation {
                Log.warning(.network, "\(host) injoignable : \(error.localizedDescription)",
                            details: "\(request.httpMethod ?? "GET") \(place) après \(elapsed(since: started))")
            }
            throw error
        }
        let (data, response) = result
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = errorDetail(from: data)
            let details = Fmt.join("\(request.httpMethod ?? "GET") \(place)", detail.map { String($0.prefix(300)) })
            switch http.statusCode {
            case 404:
                // Produit absent d'une base (Open Food Facts…) : normal, pas une panne.
                Log.info(.network, "\(host) : introuvable (404)", details: details)
            case 400..<500:
                Log.warning(.network, "\(host) : requête refusée (\(http.statusCode))", details: details)
            default:
                Log.error(.network, "\(host) : erreur \(http.statusCode)", details: details)
            }
            throw APIError.status(http.statusCode, detail)
        }
        let decoder = JSONDecoder()
        if snakeCase {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Log.error(.network, "\(host) : réponse illisible",
                      details: "\(place)\n\(String(String(describing: error).prefix(400)))")
            throw error
        }
    }

    private static func elapsed(since start: Date) -> String {
        String(format: "%.1f s", Date().timeIntervalSince(start)).replacingOccurrences(of: ".", with: ",")
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
