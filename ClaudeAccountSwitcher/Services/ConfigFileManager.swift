import Foundation

class ConfigFileManager {
    static let shared = ConfigFileManager()

    private let homeDir = FileManager.default.homeDirectoryForCurrentUser
    private let fileManager = FileManager.default

    private var claudeConfigPath: URL {
        homeDir.appendingPathComponent(".claude.json")
    }

    private var claudeDir: URL {
        homeDir.appendingPathComponent(".claude")
    }

    private var profilesDir: URL {
        homeDir.appendingPathComponent(".claude-switcher/profiles")
    }

    // Files and directories to backup per profile
    private let managedItems = [
        ".claude.json",
        ".claude/stats-cache.json",
        ".claude/settings.json",
        ".claude/statsig"
    ]

    private init() {}

    // MARK: - Backup Configuration

    func backupConfig(to profileId: UUID) throws {
        let profileDir = profilesDir.appendingPathComponent(profileId.uuidString)
        try fileManager.createDirectory(at: profileDir, withIntermediateDirectories: true)

        for item in managedItems {
            let sourcePath = homeDir.appendingPathComponent(item)
            let destPath = profileDir.appendingPathComponent(item.replacingOccurrences(of: ".claude/", with: ""))

            guard fileManager.fileExists(atPath: sourcePath.path) else { continue }

            // Remove existing backup
            if fileManager.fileExists(atPath: destPath.path) {
                try fileManager.removeItem(at: destPath)
            }

            // Create parent directory if needed
            try fileManager.createDirectory(at: destPath.deletingLastPathComponent(), withIntermediateDirectories: true)

            // Copy file or directory
            try fileManager.copyItem(at: sourcePath, to: destPath)
        }
    }

    // MARK: - Restore Configuration

    func restoreConfig(from profileId: UUID) throws {
        let profileDir = profilesDir.appendingPathComponent(profileId.uuidString)

        guard fileManager.fileExists(atPath: profileDir.path) else {
            throw ConfigError.profileNotFound
        }

        for item in managedItems {
            let backupName = item.replacingOccurrences(of: ".claude/", with: "")
            let sourcePath = profileDir.appendingPathComponent(backupName)
            let destPath = homeDir.appendingPathComponent(item)

            guard fileManager.fileExists(atPath: sourcePath.path) else { continue }

            // Remove existing file
            if fileManager.fileExists(atPath: destPath.path) {
                try fileManager.removeItem(at: destPath)
            }

            // Create parent directory if needed
            try fileManager.createDirectory(at: destPath.deletingLastPathComponent(), withIntermediateDirectories: true)

            // Copy from backup
            try fileManager.copyItem(at: sourcePath, to: destPath)
        }
    }

    // MARK: - Read Usage Stats

    func readUsageStats() -> UsageStats? {
        let statsPath = claudeDir.appendingPathComponent("stats-cache.json")

        guard let data = try? Data(contentsOf: statsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var stats = UsageStats()

        // Parse total messages and sessions
        stats.totalMessages = json["totalMessages"] as? Int ?? 0
        stats.totalSessions = json["totalSessions"] as? Int ?? 0

        // Parse daily activity for today and this week
        if let dailyActivity = json["dailyActivity"] as? [[String: Any]] {
            let today = dateString(for: Date())
            let weekStart = dateString(for: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())

            for activity in dailyActivity {
                guard let date = activity["date"] as? String,
                      let messageCount = activity["messageCount"] as? Int else { continue }

                if date == today {
                    stats.todayMessages = messageCount
                }

                if date >= weekStart {
                    stats.weekMessages += messageCount
                }
            }
        }

        // Parse model usage
        if let modelUsage = json["modelUsage"] as? [String: [String: Any]] {
            for (model, usage) in modelUsage {
                stats.tokensByModel[model] = TokenUsage(
                    inputTokens: usage["inputTokens"] as? Int ?? 0,
                    outputTokens: usage["outputTokens"] as? Int ?? 0,
                    cacheReadTokens: usage["cacheReadInputTokens"] as? Int ?? 0,
                    cacheCreationTokens: usage["cacheCreationInputTokens"] as? Int ?? 0
                )
            }
        }

        return stats
    }

    // MARK: - Clear Config for New Account

    func clearClaudeConfig() throws {
        // Remove the main config file to force fresh login
        if fileManager.fileExists(atPath: claudeConfigPath.path) {
            try fileManager.removeItem(at: claudeConfigPath)
        }

        // Remove statsig session data
        let statsigDir = claudeDir.appendingPathComponent("statsig")
        if fileManager.fileExists(atPath: statsigDir.path) {
            try fileManager.removeItem(at: statsigDir)
        }
    }

    // MARK: - Check if Profile Has Backup

    func hasBackup(for profileId: UUID) -> Bool {
        let profileDir = profilesDir.appendingPathComponent(profileId.uuidString)
        return fileManager.fileExists(atPath: profileDir.path)
    }

    // MARK: - Delete Profile

    func deleteProfile(_ profileId: UUID) throws {
        let profileDir = profilesDir.appendingPathComponent(profileId.uuidString)
        if fileManager.fileExists(atPath: profileDir.path) {
            try fileManager.removeItem(at: profileDir)
        }
    }

    // MARK: - Get Current User ID

    func getCurrentUserId() -> String? {
        guard let data = try? Data(contentsOf: claudeConfigPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userId = json["userID"] as? String else {
            return nil
        }
        return userId
    }

    // MARK: - Helpers

    private func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum ConfigError: LocalizedError {
    case profileNotFound
    case backupFailed
    case restoreFailed

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "Profile configuration not found"
        case .backupFailed:
            return "Failed to backup configuration"
        case .restoreFailed:
            return "Failed to restore configuration"
        }
    }
}
