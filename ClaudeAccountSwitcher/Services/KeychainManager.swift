import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    static let serviceName = "Claude Code-credentials"

    private let profilesDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude-switcher/profiles")
    }()

    private init() {}

    // MARK: - Read Credentials

    func getCredential(service: String = serviceName, account: String? = nil) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let account = account {
            query[kSecAttrAccount as String] = account
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }

        return result as? Data
    }

    func getCredentialString(service: String = serviceName, account: String? = nil) -> String? {
        guard let data = getCredential(service: service, account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Save Credentials

    func saveCredential(service: String = serviceName, account: String, data: Data) -> Bool {
        // First try to delete existing
        deleteCredential(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func saveCredentialString(service: String = serviceName, account: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return saveCredential(service: service, account: account, data: data)
    }

    // MARK: - Delete Credentials

    @discardableResult
    func deleteCredential(service: String = serviceName, account: String? = nil) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        if let account = account {
            query[kSecAttrAccount as String] = account
        }

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - List All Claude Code Entries

    func listAllClaudeCredentials() -> [(service: String, account: String)] {
        var results: [(String, String)] = []

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var items: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &items)

        guard status == errSecSuccess,
              let itemList = items as? [[String: Any]] else {
            return results
        }

        for item in itemList {
            if let service = item[kSecAttrService as String] as? String,
               service.contains("Claude Code"),
               let account = item[kSecAttrAccount as String] as? String {
                results.append((service, account))
            }
        }

        return results
    }

    // MARK: - Profile Backup/Restore

    func backupCredentials(to profileId: UUID) throws {
        let profileDir = profilesDir.appendingPathComponent(profileId.uuidString)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let backupFile = profileDir.appendingPathComponent("keychain-backup.json")
        var backupData: [[String: String]] = []

        // Backup all Claude Code credentials
        let credentials = listAllClaudeCredentials()
        for (service, account) in credentials {
            if let credData = getCredential(service: service, account: account),
               let credString = String(data: credData, encoding: .utf8) {
                backupData.append([
                    "service": service,
                    "account": account,
                    "credential": credString
                ])
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(backupData)
        try jsonData.write(to: backupFile, options: .atomic)
    }

    func restoreCredentials(from profileId: UUID) throws {
        let profileDir = profilesDir.appendingPathComponent(profileId.uuidString)
        let backupFile = profileDir.appendingPathComponent("keychain-backup.json")

        guard FileManager.default.fileExists(atPath: backupFile.path) else {
            throw KeychainError.backupNotFound
        }

        let jsonData = try Data(contentsOf: backupFile)
        let backupData = try JSONDecoder().decode([[String: String]].self, from: jsonData)

        // First, delete all existing Claude Code credentials
        let existingCredentials = listAllClaudeCredentials()
        for (service, account) in existingCredentials {
            deleteCredential(service: service, account: account)
        }

        // Restore from backup
        for entry in backupData {
            guard let service = entry["service"],
                  let account = entry["account"],
                  let credential = entry["credential"] else { continue }

            _ = saveCredentialString(service: service, account: account, value: credential)
        }
    }

    func hasBackup(for profileId: UUID) -> Bool {
        let backupFile = profilesDir
            .appendingPathComponent(profileId.uuidString)
            .appendingPathComponent("keychain-backup.json")
        return FileManager.default.fileExists(atPath: backupFile.path)
    }
}

enum KeychainError: LocalizedError {
    case backupNotFound
    case restoreFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .backupNotFound:
            return "Credential backup not found for this profile"
        case .restoreFailed:
            return "Failed to restore credentials from backup"
        case .saveFailed:
            return "Failed to save credentials to keychain"
        }
    }
}
