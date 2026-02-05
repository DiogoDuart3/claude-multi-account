import Foundation
import Security

// MARK: - Rate Window Model (matches CodexBar)

struct RateWindow {
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAt: Date?
    let resetDescription: String?
    
    init(usedPercent: Double, resetsAt: Date? = nil, resetDescription: String? = nil) {
        self.usedPercent = max(0, min(100, usedPercent))
        self.remainingPercent = max(0, min(100, 100 - usedPercent))
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }
}

// MARK: - Usage Snapshot (matches CodexBar's ClaudeUsageSnapshot)

struct UsageSnapshot {
    let primary: RateWindow      // 5-hour session window
    let secondary: RateWindow?   // 7-day weekly window
    let updatedAt: Date
    let accountEmail: String?
    let loginMethod: String?
}

// MARK: - OAuth Response Models

private struct OAuthUsageResponse: Decodable {
    let fiveHour: OAuthUsageWindow?
    let sevenDay: OAuthUsageWindow?
    let sevenDayOAuthApps: OAuthUsageWindow?
    let sevenDayOpus: OAuthUsageWindow?
    let sevenDaySonnet: OAuthUsageWindow?
    
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOAuthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

private struct OAuthUsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?
    
    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

// MARK: - OAuth Credentials (matches CodexBar format)

private struct ClaudeOAuthCredentials {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let scopes: [String]
    let rateLimitTier: String?
    
    var isExpired: Bool {
        guard let expiresAt else { return true }
        return Date() >= expiresAt
    }
}

// MARK: - Credentials JSON Structure

private struct CredentialsRoot: Decodable {
    let claudeAiOauth: CredentialsOAuth?
}

private struct CredentialsOAuth: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Double?  // Milliseconds since epoch
    let scopes: [String]?
    let rateLimitTier: String?
}

// MARK: - Usage Parser

class UsageParser {
    static let shared = UsageParser()
    
    private static let keychainService = "Claude Code-credentials"
    private static let credentialsPath = ".claude/.credentials.json"
    
    private init() {}
    
    // MARK: - Public API
    
    /// Fetches usage using the same strategy as CodexBar:
    /// 1. Try OAuth API (preferred)
    /// 2. Fall back to CLI parsing
    func fetchUsage() async throws -> RateLimitInfo {
        // Try OAuth first (like CodexBar)
        if let oauthCreds = loadOAuthCredentials() {
            if oauthCreds.scopes.contains("user:profile") && !oauthCreds.isExpired {
                do {
                    let snapshot = try await fetchViaOAuth(credentials: oauthCreds)
                    return convertToRateLimitInfo(snapshot)
                } catch {
                    print("OAuth fetch failed, falling back to CLI: \(error)")
                }
            }
        }
        
        // Fall back to CLI parsing
        return try await fetchViaCLI()
    }
    
    // MARK: - OAuth API Fetch (matches CodexBar)
    
    private func fetchViaOAuth(credentials: ClaudeOAuthCredentials) async throws -> UsageSnapshot {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw UsageParserError.commandFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("ClaudeAccountSwitcher/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw UsageParserError.commandFailed("Invalid response")
        }
        
        guard http.statusCode == 200 else {
            throw UsageParserError.commandFailed("OAuth API returned \(http.statusCode)")
        }
        
        return try mapOAuthResponse(data, credentials: credentials)
    }
    
    private func mapOAuthResponse(_ data: Data, credentials: ClaudeOAuthCredentials) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        let response = try decoder.decode(OAuthUsageResponse.self, from: data)
        
        guard let fiveHour = response.fiveHour,
              let utilization = fiveHour.utilization else {
            throw UsageParserError.parseError
        }
        
        let primaryReset = parseISO8601Date(fiveHour.resetsAt)
        let primary = RateWindow(
            usedPercent: utilization,
            resetsAt: primaryReset,
            resetDescription: primaryReset.map(formatResetDate)
        )
        
        let secondary: RateWindow? = {
            guard let sevenDay = response.sevenDay,
                  let util = sevenDay.utilization else { return nil }
            let resetDate = parseISO8601Date(sevenDay.resetsAt)
            return RateWindow(
                usedPercent: util,
                resetsAt: resetDate,
                resetDescription: resetDate.map(formatResetDate)
            )
        }()
        
        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            updatedAt: Date(),
            accountEmail: nil,
            loginMethod: inferPlan(from: credentials.rateLimitTier)
        )
    }
    
    private func parseISO8601Date(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    
    private func formatResetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d 'at' h:mma"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
    
    private func inferPlan(from tier: String?) -> String? {
        guard let tier = tier?.lowercased() else { return nil }
        if tier.contains("max") { return "Claude Max" }
        if tier.contains("pro") { return "Claude Pro" }
        if tier.contains("team") { return "Claude Team" }
        if tier.contains("enterprise") { return "Claude Enterprise" }
        return nil
    }
    
    // MARK: - Load OAuth Credentials (matches CodexBar exactly)
    
    private func loadOAuthCredentials() -> ClaudeOAuthCredentials? {
        // Try Keychain first (like CodexBar)
        if let keychainData = loadFromKeychain() {
            if let creds = parseCredentials(data: keychainData) {
                return creds
            }
        }
        
        // Fall back to file
        if let fileData = loadFromFile() {
            return parseCredentials(data: fileData)
        }
        
        return nil
    }
    
    private func loadFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              !data.isEmpty else {
            return nil
        }
        
        return data
    }
    
    private func loadFromFile() -> Data? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(Self.credentialsPath)
        return try? Data(contentsOf: url)
    }
    
    private func parseCredentials(data: Data) -> ClaudeOAuthCredentials? {
        let decoder = JSONDecoder()
        guard let root = try? decoder.decode(CredentialsRoot.self, from: data),
              let oauth = root.claudeAiOauth,
              let accessToken = oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty else {
            return nil
        }
        
        // expiresAt is in milliseconds
        let expiresAt = oauth.expiresAt.map { millis in
            Date(timeIntervalSince1970: millis / 1000.0)
        }
        
        return ClaudeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: oauth.refreshToken,
            expiresAt: expiresAt,
            scopes: oauth.scopes ?? [],
            rateLimitTier: oauth.rateLimitTier
        )
    }
    
    // MARK: - CLI Fetch (fallback)
    
    private func fetchViaCLI() async throws -> RateLimitInfo {
        let claudePath = findClaudePath()
        
        guard let path = claudePath else {
            throw UsageParserError.claudeNotFound
        }
        
        let output = try await runCommand(path, arguments: ["-p", "/usage"])
        let cleanOutput = stripANSICodes(output)
        return parseUsageOutput(cleanOutput)
    }
    
    private func convertToRateLimitInfo(_ snapshot: UsageSnapshot) -> RateLimitInfo {
        var info = RateLimitInfo()
        info.sessionUsed = Int(snapshot.primary.usedPercent)
        info.sessionLimit = 100
        info.resetTime = snapshot.primary.resetsAt
        
        if let secondary = snapshot.secondary {
            info.weeklyUsed = Int(secondary.usedPercent)
            info.weeklyLimit = 100
            info.weeklyResetTime = secondary.resetsAt
        }
        
        return info
    }
    
    // MARK: - Find Claude CLI Path
    
    private func findClaudePath() -> String? {
        // Check PATH first using /usr/bin/env
        if let envPath = try? runCommandSync("/usr/bin/env", arguments: ["which", "claude"]),
           !envPath.isEmpty {
            let path = envPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Check common paths
        let possiblePaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.npm-global/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/bin/claude"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    // MARK: - Run Command
    
    private func runCommand(_ path: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            
            // Set environment to avoid ANSI codes
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "dumb"
            env["NO_COLOR"] = "1"
            process.environment = env
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func runCommandSync(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    // MARK: - Strip ANSI Codes
    
    private func stripANSICodes(_ text: String) -> String {
        let pattern = #"\x1B\[[0-9;]*[a-zA-Z]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
    
    // MARK: - Parse Usage Output (CLI fallback)
    
    func parseUsageOutput(_ output: String) -> RateLimitInfo {
        var info = RateLimitInfo()
        
        let lines = output.components(separatedBy: .newlines)
        let normalizedLines = lines.map { $0.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        
        enum Section { case none, session, weeklyAll, weeklyOpus }
        var currentSection: Section = .none
        
        for (index, line) in lines.enumerated() {
            let normalizedLine = normalizedLines[index]
            
            // Detect section headers
            if normalizedLine.contains("current session") {
                currentSection = .session
            } else if normalizedLine.contains("current week") && normalizedLine.contains("all") {
                currentSection = .weeklyAll
            } else if normalizedLine.contains("current week") && (normalizedLine.contains("opus") || normalizedLine.contains("sonnet")) {
                currentSection = .weeklyOpus
            }
            
            // Parse percentage
            if let percentInfo = parsePercent(line) {
                let usedPercent = percentInfo.isUsed ? percentInfo.value : (100 - percentInfo.value)
                
                switch currentSection {
                case .session:
                    info.sessionUsed = usedPercent
                    info.sessionLimit = 100
                case .weeklyAll:
                    info.weeklyUsed = usedPercent
                    info.weeklyLimit = 100
                case .weeklyOpus, .none:
                    break
                }
            }
            
            // Parse reset time
            if normalizedLine.contains("reset") {
                if let resetDate = parseResetDate(from: line) {
                    switch currentSection {
                    case .session:
                        info.resetTime = resetDate
                    case .weeklyAll, .weeklyOpus:
                        info.weeklyResetTime = resetDate
                    case .none:
                        if info.sessionUsed != nil && info.resetTime == nil {
                            info.resetTime = resetDate
                        } else if info.weeklyUsed != nil && info.weeklyResetTime == nil {
                            info.weeklyResetTime = resetDate
                        }
                    }
                }
            }
        }
        
        // Estimate weekly reset if not found
        if info.weeklyUsed != nil && info.weeklyResetTime == nil {
            let calendar = Calendar.current
            if let nextMonday = calendar.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0, weekday: 2), matchingPolicy: .nextTime) {
                info.weeklyResetTime = nextMonday
            }
        }
        
        return info
    }
    
    // MARK: - Parse Percentage
    
    private func parsePercent(_ line: String) -> (value: Int, isUsed: Bool)? {
        let pattern = #"([0-9]{1,3})\s*%\s*(used|left)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
              match.numberOfRanges >= 3,
              let valueRange = Range(match.range(at: 1), in: line),
              let kindRange = Range(match.range(at: 2), in: line),
              let value = Int(line[valueRange]) else {
            return nil
        }
        
        let isUsed = line[kindRange].lowercased().contains("used")
        return (value, isUsed)
    }
    
    // MARK: - Parse Reset Date
    
    private func parseResetDate(from text: String) -> Date? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        raw = raw.replacingOccurrences(of: #"(?i)^resets?:?\s*"#, with: "", options: .regularExpression)
        raw = raw.replacingOccurrences(of: " at ", with: " ", options: .caseInsensitive)
        
        // Extract timezone
        var timeZone: TimeZone? = nil
        if let tzRange = raw.range(of: #"\(([^)]+)\)"#, options: .regularExpression) {
            let tzID = String(raw[tzRange]).trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            timeZone = TimeZone(identifier: tzID)
            raw.removeSubrange(tzRange)
        }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone ?? TimeZone.current
        formatter.defaultDate = Date()
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        
        let dateTimeFormats = [
            "MMM d, h:mma", "MMM d, h:mm a", "MMM d h:mma", "MMM d h:mm a",
            "MMM d, ha", "MMM d, h a", "MMM d ha", "MMM d h a",
            "MMM d, HH:mm", "MMM d HH:mm"
        ]
        
        for format in dateTimeFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        
        let timeFormats = ["h:mma", "h:mm a", "HH:mm", "H:mm", "ha", "h a"]
        
        for format in timeFormats {
            formatter.dateFormat = format
            if let time = formatter.date(from: raw) {
                let comps = calendar.dateComponents([.hour, .minute], from: time)
                guard let anchored = calendar.date(
                    bySettingHour: comps.hour ?? 0,
                    minute: comps.minute ?? 0,
                    second: 0,
                    of: Date()) else { continue }
                
                if anchored >= Date() {
                    return anchored
                }
                return calendar.date(byAdding: .day, value: 1, to: anchored)
            }
        }
        
        return nil
    }
}

enum UsageParserError: LocalizedError {
    case claudeNotFound
    case parseError
    case commandFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude CLI not found. Please ensure Claude Code is installed."
        case .parseError:
            return "Failed to parse usage information"
        case .commandFailed(let message):
            return "Command failed: \(message)"
        }
    }
}
