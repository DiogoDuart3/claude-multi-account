import SwiftUI

@main
struct ClaudeAccountSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Hidden window to keep SwiftUI lifecycle alive (like CodexBar)
        WindowGroup("ClaudeAccountSwitcherLifecycle") {
            EmptyView()
                .frame(width: 1, height: 1)
        }
        .defaultSize(width: 1, height: 1)
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let switcher = AccountSwitcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar controller (like CodexBar's StatusItemController)
        statusBarController = StatusBarController(switcher: switcher)

        // Initialize NotificationManager (requests authorization in init)
        _ = NotificationManager.shared

        // Start periodic refresh
        startPeriodicRefresh()
    }

    private func startPeriodicRefresh() {
        // Refresh every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.switcher.refreshUsage()
            }
        }
    }
}

// MARK: - Status Bar Controller (like CodexBar's StatusItemController)

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let switcher: AccountSwitcher

    init(switcher: AccountSwitcher) {
        self.switcher = switcher
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // Defer setup to next run loop to ensure SwiftUI environment is ready
        DispatchQueue.main.async { [weak self] in
            self?.setupStatusItem()
            self?.observeSwitcherChanges()
        }
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            button.image = menuBarIcon
            button.imageScaling = .scaleNone
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    private func observeSwitcherChanges() {
        // Refresh icon every 30 seconds to catch account updates
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateIcon()
        }
    }

    private func updateIcon() {
        statusItem.button?.image = menuBarIcon
    }

    private var menuBarIcon: NSImage {
        guard let active = switcher.activeAccount,
              let rateLimit = active.cachedRateLimit else {
            return IconRenderer.makeIcon(
                sessionRemaining: nil,
                weeklyRemaining: nil,
                stale: true
            )
        }

        let now = Date()

        let sessionRemaining: Double?
        if let used = rateLimit.sessionUsed {
            let sessionHasReset = rateLimit.resetTime.map { $0 <= now } ?? false
            sessionRemaining = sessionHasReset ? 100 : Double(100 - used)
        } else {
            sessionRemaining = nil
        }

        let weeklyRemaining: Double?
        if let used = rateLimit.weeklyUsed {
            let weeklyHasReset = rateLimit.weeklyResetTime.map { $0 <= now } ?? false
            weeklyRemaining = weeklyHasReset ? 100 : Double(100 - used)
        } else {
            weeklyRemaining = nil
        }

        let isStale = Date().timeIntervalSince(rateLimit.lastUpdated) > 600

        return IconRenderer.makeIcon(
            sessionRemaining: sessionRemaining,
            weeklyRemaining: weeklyRemaining,
            stale: isStale
        )
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        populateMenu(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Clean up if needed
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // Active account usage card
        if let active = switcher.activeAccount {
            let cardItem = makeUsageCardItem(account: active)
            menu.addItem(cardItem)
        } else {
            let placeholderItem = NSMenuItem(title: "No account configured", action: nil, keyEquivalent: "")
            placeholderItem.isEnabled = false
            menu.addItem(placeholderItem)
        }

        // Other accounts section
        let inactiveAccounts = switcher.accounts.filter { !$0.isActive }
        if !inactiveAccounts.isEmpty {
            menu.addItem(.separator())

            let headerItem = NSMenuItem(title: "Other Accounts", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
            headerItem.attributedTitle = NSAttributedString(
                string: "Other Accounts",
                attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
            )
            menu.addItem(headerItem)

            for account in inactiveAccounts {
                let item = makeAccountSwitchItem(account: account)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // Actions
        let addItem = NSMenuItem(
            title: "Add Account...",
            action: #selector(addAccount),
            keyEquivalent: "")
        addItem.target = self
        if let image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            addItem.image = image
        }
        menu.addItem(addItem)

        let refreshItem = NSMenuItem(
            title: "Refresh",
            action: #selector(refresh),
            keyEquivalent: "")
        refreshItem.target = self
        if let image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            refreshItem.image = image
        }
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        // Check for updates
        let updatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: "")
        updatesItem.target = self
        if let image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            updatesItem.image = image
        }
        menu.addItem(updatesItem)

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApp.terminate(_:)),
            keyEquivalent: "q")
        if let image = NSImage(systemSymbolName: "power", accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            quitItem.image = image
        }
        menu.addItem(quitItem)
    }

    private func makeUsageCardItem(account: Account) -> NSMenuItem {
        // Use pure AppKit instead of NSHostingView to avoid SwiftUI-in-NSMenu issues
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false

        // Build attributed string for usage card
        let titleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let subtitleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        let title = NSMutableAttributedString()

        // Header: "Claude Code" + account name
        title.append(NSAttributedString(
            string: "Claude Code",
            attributes: [.font: titleFont, .foregroundColor: NSColor.labelColor]
        ))
        title.append(NSAttributedString(
            string: "  \(account.name)\n",
            attributes: [.font: subtitleFont, .foregroundColor: NSColor.secondaryLabelColor]
        ))

        // Last updated
        if let rateLimit = account.cachedRateLimit {
            let interval = Date().timeIntervalSince(rateLimit.lastUpdated)
            let updated: String
            if interval < 60 {
                updated = "Updated just now"
            } else if interval < 3600 {
                updated = "Updated \(Int(interval / 60))m ago"
            } else {
                updated = "Updated \(Int(interval / 3600))h ago"
            }
            title.append(NSAttributedString(
                string: "\(updated)\n\n",
                attributes: [.font: subtitleFont, .foregroundColor: NSColor.secondaryLabelColor]
            ))

            // Session usage
            if let sessionUsed = rateLimit.sessionUsed {
                let now = Date()
                let sessionHasReset = rateLimit.resetTime.map { $0 <= now } ?? false
                let sessionLeft = sessionHasReset ? 100 : max(0, 100 - sessionUsed)
                title.append(NSAttributedString(
                    string: "Session: \(sessionLeft)% remaining\n",
                    attributes: [.font: bodyFont, .foregroundColor: NSColor.labelColor]
                ))
            }

            // Weekly usage
            if let weeklyUsed = rateLimit.weeklyUsed {
                let now = Date()
                let weeklyHasReset = rateLimit.weeklyResetTime.map { $0 <= now } ?? false
                let weeklyLeft = weeklyHasReset ? 100 : max(0, 100 - weeklyUsed)
                title.append(NSAttributedString(
                    string: "Weekly: \(weeklyLeft)% remaining",
                    attributes: [.font: bodyFont, .foregroundColor: NSColor.labelColor]
                ))
            }
        } else {
            title.append(NSAttributedString(
                string: "Not fetched yet",
                attributes: [.font: subtitleFont, .foregroundColor: NSColor.secondaryLabelColor]
            ))
        }

        item.attributedTitle = title
        return item
    }

    private func makeAccountSwitchItem(account: Account) -> NSMenuItem {
        let item = NSMenuItem(
            title: account.name,
            action: #selector(switchAccount(_:)),
            keyEquivalent: "")
        item.target = self
        item.representedObject = account.id

        if let image = NSImage(systemSymbolName: "person.circle", accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            item.image = image
        }

        // Add subtitle with usage info
        if let rateLimit = account.cachedRateLimit {
            var subtitle = ""
            if let sessionUsed = rateLimit.sessionUsed {
                let sessionHasReset = rateLimit.resetTime.map { $0 <= Date() } ?? false
                let sessionLeft = sessionHasReset ? 100 : max(0, 100 - sessionUsed)
                subtitle += "Session: \(sessionLeft)%"
            }
            if let weeklyUsed = rateLimit.weeklyUsed {
                let weeklyHasReset = rateLimit.weeklyResetTime.map { $0 <= Date() } ?? false
                let weeklyLeft = weeklyHasReset ? 100 : max(0, 100 - weeklyUsed)
                if !subtitle.isEmpty { subtitle += " • " }
                subtitle += "Weekly: \(weeklyLeft)%"
            }

            if !subtitle.isEmpty {
                if #available(macOS 14.4, *) {
                    item.subtitle = subtitle
                } else {
                    // Fallback for older macOS
                    let titleAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.menuFont(ofSize: NSFont.systemFontSize),
                        .foregroundColor: NSColor.labelColor
                    ]
                    let subtitleAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]

                    let attributedTitle = NSMutableAttributedString(string: account.name, attributes: titleAttributes)
                    attributedTitle.append(NSAttributedString(string: "\n", attributes: titleAttributes))
                    attributedTitle.append(NSAttributedString(string: subtitle, attributes: subtitleAttributes))

                    item.attributedTitle = attributedTitle
                }
            }
        }

        return item
    }

    @objc private func switchAccount(_ sender: NSMenuItem) {
        guard let accountId = sender.representedObject as? UUID else { return }
        guard let account = switcher.accounts.first(where: { $0.id == accountId }) else { return }
        Task {
            await switcher.switchTo(account: account)
            statusItem.button?.image = menuBarIcon
        }
    }

    @objc private func addAccount() {
        showAddAccountDialog()
    }

    @objc private func refresh() {
        Task {
            await switcher.refreshAllAccounts()
            statusItem.button?.image = menuBarIcon
        }
    }

    @objc private func checkForUpdates() {
        UpdaterManager.shared.checkForUpdates()
    }

    private func showAddAccountDialog() {
        let alert = NSAlert()
        alert.messageText = "Add New Account"
        alert.informativeText = "Enter a name for this account. After clicking Add, Terminal will open to complete the Claude login."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Add Account")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.placeholderString = "e.g., Work, Personal, Client Project"
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let accountName = textField.stringValue.isEmpty ? "New Account" : textField.stringValue
            Task {
                await switcher.addAccount(name: accountName)
                statusItem.button?.image = menuBarIcon
            }
        }
    }
}
