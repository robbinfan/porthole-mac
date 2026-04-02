import Foundation
import Security

struct GitLabConfig: Codable, Sendable {
    let host: String
    var tokenKeychainService: String = "cmux-gitlab"

    enum CodingKeys: String, CodingKey {
        case host
        case tokenKeychainService = "token_keychain_service"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        tokenKeychainService = try container.decodeIfPresent(String.self, forKey: .tokenKeychainService) ?? "cmux-gitlab"
    }

    init(host: String, tokenKeychainService: String = "cmux-gitlab") {
        self.host = host
        self.tokenKeychainService = tokenKeychainService
    }

    // MARK: - Config File I/O

    static let configPath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/cmux/gitlab.json")
    }()

    static func load() -> GitLabConfig? {
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? JSONDecoder().decode(GitLabConfig.self, from: data)
    }

    // MARK: - Keychain

    func saveToken(_ token: String) -> Bool {
        let data = token.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenKeychainService,
            kSecAttrAccount as String: "gitlab-token",
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenKeychainService,
            kSecAttrAccount as String: "gitlab-token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenKeychainService,
            kSecAttrAccount as String: "gitlab-token"
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
