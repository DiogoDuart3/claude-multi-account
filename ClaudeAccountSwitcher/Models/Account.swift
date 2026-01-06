import Foundation

struct Account: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var username: String
    var isActive: Bool
    var lastSwitched: Date?
    var cachedUsage: UsageStats?
    var cachedRateLimit: RateLimitInfo?

    init(id: UUID = UUID(), name: String, username: String, isActive: Bool = false) {
        self.id = id
        self.name = name
        self.username = username
        self.isActive = isActive
    }

    static func == (lhs: Account, rhs: Account) -> Bool {
        lhs.id == rhs.id
    }
}

struct UsageStats: Codable {
    var totalMessages: Int
    var totalSessions: Int
    var todayMessages: Int
    var weekMessages: Int
    var tokensByModel: [String: TokenUsage]

    init(totalMessages: Int = 0, totalSessions: Int = 0, todayMessages: Int = 0, weekMessages: Int = 0, tokensByModel: [String: TokenUsage] = [:]) {
        self.totalMessages = totalMessages
        self.totalSessions = totalSessions
        self.todayMessages = todayMessages
        self.weekMessages = weekMessages
        self.tokensByModel = tokensByModel
    }
}

struct TokenUsage: Codable {
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheCreationTokens: Int

    init(inputTokens: Int = 0, outputTokens: Int = 0, cacheReadTokens: Int = 0, cacheCreationTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
    }
}

struct RateLimitInfo: Codable {
    var sessionUsed: Int?
    var sessionLimit: Int?
    var weeklyUsed: Int?
    var weeklyLimit: Int?
    var resetTime: Date?          // Session reset time
    var weeklyResetTime: Date?    // Weekly reset time
    var lastUpdated: Date

    var sessionRemaining: Int? {
        guard let used = sessionUsed, let limit = sessionLimit else { return nil }
        return max(0, limit - used)
    }

    var weeklyRemaining: Int? {
        guard let used = weeklyUsed, let limit = weeklyLimit else { return nil }
        return max(0, limit - used)
    }

    var sessionPercentUsed: Double? {
        guard let used = sessionUsed, let limit = sessionLimit, limit > 0 else { return nil }
        return Double(used) / Double(limit)
    }

    var weeklyPercentUsed: Double? {
        guard let used = weeklyUsed, let limit = weeklyLimit, limit > 0 else { return nil }
        return Double(used) / Double(limit)
    }

    init(sessionUsed: Int? = nil, sessionLimit: Int? = nil, weeklyUsed: Int? = nil, weeklyLimit: Int? = nil, resetTime: Date? = nil, weeklyResetTime: Date? = nil) {
        self.sessionUsed = sessionUsed
        self.sessionLimit = sessionLimit
        self.weeklyUsed = weeklyUsed
        self.weeklyLimit = weeklyLimit
        self.resetTime = resetTime
        self.weeklyResetTime = weeklyResetTime
        self.lastUpdated = Date()
    }
}

// MARK: - App Configuration

struct AppConfig: Codable {
    var accounts: [Account]
    var activeAccountId: UUID?
    var lastRefreshed: Date?

    init(accounts: [Account] = [], activeAccountId: UUID? = nil) {
        self.accounts = accounts
        self.activeAccountId = activeAccountId
    }

    static let configPath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude-switcher/config.json")
    }()

    static func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: configPath.path),
              let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }

    func save() throws {
        let directory = AppConfig.configPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: AppConfig.configPath, options: .atomic)
    }
}
