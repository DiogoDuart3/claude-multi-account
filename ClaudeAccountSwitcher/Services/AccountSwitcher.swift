import Foundation
import SwiftUI

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
            accounts[index].cachedRateLimit = rateLimitInfo
            activeAccount = accounts[index]
            saveAccounts()
        } catch {
            // Rate limit fetch failed, but we still have local stats
            print("Failed to fetch rate limit info: \(error)")
        }
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

            // 4. Open terminal to run claude login
            openTerminalForLogin()

            // 5. Wait a bit then check for new credentials
            isAddingAccount = true

            // Start polling for new credentials
            Task {
                await pollForNewCredentials(accountId: newAccount.id)
            }

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func openTerminalForLogin() {
        let script = """
        tell application "Terminal"
            activate
            do script "claude login && echo '\\n✅ Login complete! You can close this window.'"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    private func pollForNewCredentials(accountId: UUID) async {
        // Poll every 2 seconds for up to 5 minutes
        let maxAttempts = 150
        var attempts = 0

        while attempts < maxAttempts {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            attempts += 1

            let credentials = keychainManager.listAllClaudeCredentials()
            if !credentials.isEmpty {
                // Found new credentials!
                let (_, username) = credentials[0]

                await MainActor.run {
                    if let index = accounts.firstIndex(where: { $0.id == accountId }) {
                        accounts[index].username = username
                        accounts[index].cachedUsage = configManager.readUsageStats()

                        // Backup the new account
                        try? keychainManager.backupCredentials(to: accountId)
                        try? configManager.backupConfig(to: accountId)

                        activeAccount = accounts[index]
                        saveAccounts()
                    }
                    isAddingAccount = false
                }

                // Refresh usage
                await refreshUsage()
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
