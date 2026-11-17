import Foundation
import Security
import UIKit
import Observation

/// Petit coffre-fort : le jeton Open Prices est rangé dans le trousseau de l'iPhone, jamais en clair.
enum Keychain {
    private static let service = "com.lemwincher.app"

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func save(_ value: String, for key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
        var attributes = baseQuery(key)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}

/// Compte Open Food Facts pour partager ses relevés sur Open Prices.
@Observable
final class OpenPricesAccount {
    private static let tokenKey = "openprices.token"
    private static let usernameKey = "openprices.username"

    private(set) var username: String?
    private(set) var token: String?
    var isWorking = false
    var lastError: String?

    var isLoggedIn: Bool { token != nil }

    init() {
        username = UserDefaults.standard.string(forKey: OpenPricesAccount.usernameKey)
        token = Keychain.read(OpenPricesAccount.tokenKey)
    }

    @MainActor
    func login(username: String, password: String) async -> Bool {
        let user = username.trimmed
        guard !user.isEmpty, !password.isEmpty else {
            lastError = "Entrez votre identifiant et votre mot de passe Open Food Facts."
            return false
        }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let session = try await OpenPricesAPI.login(username: user, password: password)
            Keychain.save(session.accessToken, for: OpenPricesAccount.tokenKey)
            UserDefaults.standard.set(user, forKey: OpenPricesAccount.usernameKey)
            token = session.accessToken
            self.username = user
            return true
        } catch {
            lastError = "Connexion impossible : \(error.localizedDescription)"
            return false
        }
    }

    func logout() {
        Keychain.delete(OpenPricesAccount.tokenKey)
        UserDefaults.standard.removeObject(forKey: OpenPricesAccount.usernameKey)
        token = nil
        username = nil
    }

    /// Publie un relevé : envoi de la photo (preuve) puis du prix. Renvoie l'identifiant du prix créé.
    func share(_ entry: MyPrice, photo: UIImage) async throws -> Int {
        guard let token else { throw APIError.status(401, nil) }
        guard let jpeg = photo.resizedForUpload().jpegData(compressionQuality: 0.7) else {
            throw URLError(.cannotDecodeContentData)
        }
        do {
            let proofID = try await OpenPricesAPI.uploadProof(token: token, jpeg: jpeg, store: entry.store,
                                                              date: entry.date, currency: entry.currency)
            return try await OpenPricesAPI.createPrice(token: token, entry: entry, proofID: proofID)
        } catch APIError.status(let code, let detail) where code == 401 || code == 403 {
            await MainActor.run { self.logout() }
            throw APIError.status(code, detail)
        }
    }
}

extension UIImage {
    /// Réduit la photo (côté le plus long 1600 px) avant l'envoi.
    func resizedForUpload(maxDimension: CGFloat = 1600) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
