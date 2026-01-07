import SwiftUI

@main
struct ClaudeAccountSwitcherApp: App {
    @StateObject private var switcher = AccountSwitcher()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(switcher)
        } label: {
            Image(nsImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: NSImage {
        if let active = switcher.activeAccount,
           let rateLimit = active.cachedRateLimit {
            // sessionUsed and weeklyUsed are already percentages (0-100)
            // So remaining = 100 - used
            let sessionRemaining: Double?
            if let used = rateLimit.sessionUsed {
                sessionRemaining = Double(100 - used)
            } else {
                sessionRemaining = nil
            }

            let weeklyRemaining: Double?
            if let used = rateLimit.weeklyUsed {
                weeklyRemaining = Double(100 - used)
            } else {
                weeklyRemaining = nil
            }

            // Check if data is stale (older than 10 minutes)
            let isStale = Date().timeIntervalSince(rateLimit.lastUpdated) > 600

            // Debug output
            print("Icon: session=\(sessionRemaining ?? -1), weekly=\(weeklyRemaining ?? -1), stale=\(isStale)")

            return IconRenderer.makeIcon(
                sessionRemaining: sessionRemaining,
                weeklyRemaining: weeklyRemaining,
                stale: isStale
            )
        }

        // No active account or no rate limit data
        return IconRenderer.makeIcon(
            sessionRemaining: nil,
            weeklyRemaining: nil,
            stale: true
        )
    }
}
