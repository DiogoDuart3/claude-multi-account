import Foundation
import SwiftUI

// MARK: - Limit State Tracking

struct LimitState: Equatable {
    var sessionHitLimit: Bool = false
    var weeklyHitLimit: Bool = false
    var sessionResetTime: Date?
    var weeklyResetTime: Date?
}

@MainActor
class AccountSwitcher: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var activeAccount: Account?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAddingAccount = false

    private let keychainManager = KeychainManager.shared
    private let configManager = ConfigFileManager.shared
    private let usageParser = UsageParser.shared
    private let notificationManager = NotificationManager.shared
    
    // Track previous limit states per account
    private var previousLimitStates: [UUID: LimitState] = [:]
    
    // Threshold for considering limit "hit" (percentage used)
    private let limitHitThreshold: Int = 100

    init() {
        loadAccounts()
    }

    // MARK: - Load/Save Accounts

    func loadAccounts() {
        var config = AppConfig.load()

        // If no accounts exist, detect current account
        if config.accounts.isEmpty {
            if let currentAccount = detectCurrentAccount() {
                config.accounts.append(currentAccount)
                config.activeAccountId = currentAccount.id
                try? config.save()
            }
        }

        accounts = config.accounts
        if let activeId = config.activeAccountId {
            activeAccount = accounts.first { $0.id == activeId }
        }

        // Mark the active one
        for i in accounts.indices {
            accounts[i].isActive = accounts[i].id == activeAccount?.id
        }
        
        // Initialize previous limit states from cached data to avoid false notifications
        initializeLimitStates()
    }
    
    private func initializeLimitStates() {
        for account in accounts {
            guard let rateLimit = account.cachedRateLimit else { continue }
            
            var state = LimitState()
            
            if let sessionUsed = rateLimit.sessionUsed {
                state.sessionHitLimit = sessionUsed >= limitHitThreshold
                state.sessionResetTime = rateLimit.resetTime
            }
            
            if let weeklyUsed = rateLimit.weeklyUsed {
                state.weeklyHitLimit = weeklyUsed >= limitHitThreshold
                state.weeklyResetTime = rateLimit.weeklyResetTime
            }
            
            previousLimitStates[account.id] = state
            
            // Schedule reset notifications for limits that are currently hit
            if state.sessionHitLimit, let resetTime = rateLimit.resetTime {
                notificationManager.scheduleSessionResetNotification(
                    accountName: account.name,
                    resetTime: resetTime
                )
            }
            
            if state.weeklyHitLimit, let resetTime = rateLimit.weeklyResetTime {
                notificationManager.scheduleWeeklyResetNotification(
                    accountName: account.name,
                    resetTime: resetTime
                )
            }
        }
    }

    func saveAccounts() {
        var config = AppConfig.load()
        config.accounts = accounts
        config.activeAccountId = activeAccount?.id
        config.lastRefreshed = Date()
        try? config.save()
    }

    // MARK: - Detect Current Account

    private func detectCurrentAccount() -> Account? {
        // Check if there's a current Claude Code credential
        let credentials = keychainManager.listAllClaudeCredentials()

        guard !credentials.isEmpty else { return nil }

        // Use the first credential's account name
        let (_, username) = credentials[0]

        // Get user ID from config if available
        let userId = configManager.getCurrentUserId()
        let displayName = userId?.prefix(8).description ?? username

        var account = Account(
            name: "Account \(displayName)",
            username: username,
            isActive: true
        )

        // Load current usage stats
        account.cachedUsage = configManager.readUsageStats()

        return account
    }

    // MARK: - Switch Account

    func switchTo(account: Account) async {
        guard account.id != activeAccount?.id else { return }

        isLoading = true
        errorMessage = nil

        do {
            // 1. Backup current account's data
            if let current = activeAccount {
                try keychainManager.backupCredentials(to: current.id)
                try configManager.backupConfig(to: current.id)
            }

            // 2. Restore target account's data
            try keychainManager.restoreCredentials(from: account.id)
            try configManager.restoreConfig(from: account.id)

            // 3. Update state
            if let currentIndex = accounts.firstIndex(where: { $0.id == activeAccount?.id }) {
                accounts[currentIndex].isActive = false
            }

            if let newIndex = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[newIndex].isActive = true
                accounts[newIndex].lastSwitched = Date()
                activeAccount = accounts[newIndex]
            }

            saveAccounts()

            // 4. Refresh usage for new account
            await refreshUsage()

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Refresh Usage

    func refreshUsage() async {
        guard let account = activeAccount,
              let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }

        // Get local stats
        accounts[index].cachedUsage = configManager.readUsageStats()

        // Get rate limit info from CLI
        do {
            let rateLimitInfo = try await usageParser.fetchUsage()
            
            // Store old rate limit for comparison
            let oldRateLimit = accounts[index].cachedRateLimit
            
            accounts[index].cachedRateLimit = rateLimitInfo
            activeAccount = accounts[index]
            saveAccounts()
            
            // Check for limit state changes and send notifications
            checkAndNotifyLimitChanges(
                account: accounts[index],
                oldRateLimit: oldRateLimit,
                newRateLimit: rateLimitInfo
            )
        } catch {
            // Rate limit fetch failed, but we still have local stats
            print("Failed to fetch rate limit info: \(error)")
        }
    }
    
    // MARK: - Limit Change Detection & Notifications
    
    private func checkAndNotifyLimitChanges(
        account: Account,
        oldRateLimit: RateLimitInfo?,
        newRateLimit: RateLimitInfo
    ) {
        let previousState = previousLimitStates[account.id] ?? LimitState()
        var currentState = LimitState()
        
        // Determine current limit states
        if let sessionUsed = newRateLimit.sessionUsed {
            currentState.sessionHitLimit = sessionUsed >= limitHitThreshold
            currentState.sessionResetTime = newRateLimit.resetTime
        }
        
        if let weeklyUsed = newRateLimit.weeklyUsed {
            currentState.weeklyHitLimit = weeklyUsed >= limitHitThreshold
            currentState.weeklyResetTime = newRateLimit.weeklyResetTime
        }
        
        // Check for session limit hit
        if currentState.sessionHitLimit && !previousState.sessionHitLimit {
            notificationManager.notifySessionLimitHit(
                accountName: account.name,
                resetTime: newRateLimit.resetTime
            )
            
            // Schedule notification for when limit resets
            if let resetTime = newRateLimit.resetTime {
                notificationManager.scheduleSessionResetNotification(
                    accountName: account.name,
                    resetTime: resetTime
                )
            }
        }
        
        // Check for session limit reset (was hit, now not hit)
        if !currentState.sessionHitLimit && previousState.sessionHitLimit {
            notificationManager.notifySessionLimitReset(accountName: account.name)
            // Cancel any pending reset notifications
            notificationManager.cancelScheduledNotifications(for: account.name)
        }
        
        // Check for weekly limit hit
        if currentState.weeklyHitLimit && !previousState.weeklyHitLimit {
            notificationManager.notifyWeeklyLimitHit(
                accountName: account.name,
                resetTime: newRateLimit.weeklyResetTime
            )
            
            // Schedule notification for when limit resets
            if let resetTime = newRateLimit.weeklyResetTime {
                notificationManager.scheduleWeeklyResetNotification(
                    accountName: account.name,
                    resetTime: resetTime
                )
            }
        }
        
        // Check for weekly limit reset (was hit, now not hit)
        if !currentState.weeklyHitLimit && previousState.weeklyHitLimit {
            notificationManager.notifyWeeklyLimitReset(accountName: account.name)
        }
        
        // Update limit reset time schedules if they changed
        if currentState.sessionHitLimit,
           let newResetTime = currentState.sessionResetTime,
           previousState.sessionResetTime != newResetTime {
            notificationManager.scheduleSessionResetNotification(
                accountName: account.name,
                resetTime: newResetTime
            )
        }
        
        if currentState.weeklyHitLimit,
           let newResetTime = currentState.weeklyResetTime,
           previousState.weeklyResetTime != newResetTime {
            notificationManager.scheduleWeeklyResetNotification(
                accountName: account.name,
                resetTime: newResetTime
            )
        }
        
        // Save current state for next comparison
        previousLimitStates[account.id] = currentState
    }

    func refreshAllAccounts() async {
        isLoading = true

        // Refresh current account
        await refreshUsage()

        // For other accounts, we can only show cached data
        // since we can't query their usage without switching

        isLoading = false
    }

    // MARK: - Add Account

    func startAddAccount() {
        isAddingAccount = true
    }

    func addAccount(name: String) async {
        isLoading = true
        errorMessage = nil

        do {
            // 1. Backup current account if exists
            if let current = activeAccount {
                try keychainManager.backupCredentials(to: current.id)
                try configManager.backupConfig(to: current.id)

                // Mark current as inactive
                if let index = accounts.firstIndex(where: { $0.id == current.id }) {
                    accounts[index].isActive = false
                }
            }

            // 2. Clear Claude config to force new login
            try configManager.clearClaudeConfig()

            // Also clear keychain credentials
            for (service, account) in keychainManager.listAllClaudeCredentials() {
                keychainManager.deleteCredential(service: service, account: account)
            }

            // 3. Create new account placeholder
            let newAccount = Account(
                name: name,
                username: "pending",
                isActive: true
            )

            accounts.append(newAccount)
            activeAccount = newAccount
            saveAccounts()

            // 4. Start login process
            isAddingAccount = true
            
            // Run login in background
            Task {
                do {
                    print("Starting Claude login...")
                    try await LoginRunner.shared.startLogin { output in
                        print("[Claude CLI]: \(output)")
                    }
                    print("Claude login process completed successfully")
                    
                    // 5. Check for new credentials immediately
                    await pollForNewCredentials(accountId: newAccount.id)
                } catch {
                    print("Login failed: \(error)")
                    await MainActor.run {
                        self.errorMessage = "Login failed: \(error.localizedDescription)"
                        // Cleanup if failed
                        if let index = self.accounts.firstIndex(where: { $0.id == newAccount.id }) {
                            self.accounts.remove(at: index)
                        }
                        self.isAddingAccount = false
                        self.saveAccounts()
                    }
                }
            }

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func pollForNewCredentials(accountId: UUID) async {
        // Poll every 2 seconds for up to 5 minutes
        let maxAttempts = 150
        var attempts = 0
        
        // Track when we started polling to detect new credentials
        let credentialsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        let initialModDate = (try? FileManager.default.attributesOfItem(atPath: credentialsPath.path))?[.modificationDate] as? Date

        while attempts < maxAttempts {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            attempts += 1

            // Check if credentials file was modified (new login)
            let currentModDate = (try? FileManager.default.attributesOfItem(atPath: credentialsPath.path))?[.modificationDate] as? Date
            
            let hasNewCredentials: Bool
            if let initial = initialModDate, let current = currentModDate {
                hasNewCredentials = current > initial
            } else if initialModDate == nil && currentModDate != nil {
                // File was created
                hasNewCredentials = true
            } else {
                // Also check old keychain credentials as fallback
                hasNewCredentials = !keychainManager.listAllClaudeCredentials().isEmpty
            }
            
            if hasNewCredentials {
                // Found new credentials!
                await MainActor.run {
                    if let index = accounts.firstIndex(where: { $0.id == accountId }) {
                        accounts[index].username = "authenticated"
                        accounts[index].cachedUsage = configManager.readUsageStats()

                        // Backup the new account
                        try? keychainManager.backupCredentials(to: accountId)
                        try? configManager.backupConfig(to: accountId)

                        activeAccount = accounts[index]
                        saveAccounts()
                    }
                    isAddingAccount = false
                }

                // Refresh usage - this will use the OAuth API
                await refreshUsage()
                
                // Save again after refresh to persist the usage data
                await MainActor.run {
                    saveAccounts()
                }
                return
            }
        }

        // Timeout - login didn't complete
        await MainActor.run {
            errorMessage = "Login timed out. Please try again."
            isAddingAccount = false

            // Remove the pending account
            accounts.removeAll { $0.id == accountId }
            saveAccounts()
        }
    }

    func cancelAddAccount() {
        isAddingAccount = false
    }

    // MARK: - Remove Account

    func removeAccount(_ account: Account) {
        guard account.id != activeAccount?.id else {
            errorMessage = "Cannot remove the active account. Switch to another account first."
            return
        }

        // Delete profile data
        try? configManager.deleteProfile(account.id)

        // Remove from list
        accounts.removeAll { $0.id == account.id }
        saveAccounts()
    }

    // MARK: - Rename Account

    func renameAccount(_ account: Account, to newName: String) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].name = newName

        if activeAccount?.id == account.id {
            activeAccount = accounts[index]
        }

        saveAccounts()
    }
}
