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
            // Get session remaining percentage
            let sessionRemaining: Double?
            if let remaining = rateLimit.sessionRemaining {
                sessionRemaining = Double(remaining)
            } else if let used = rateLimit.sessionUsed {
                sessionRemaining = 100 - Double(used)
            } else {
                sessionRemaining = nil
            }

            // Get weekly remaining percentage
            let weeklyRemaining: Double?
            if let remaining = rateLimit.weeklyRemaining {
                weeklyRemaining = Double(remaining)
            } else if let used = rateLimit.weeklyUsed {
                weeklyRemaining = 100 - Double(used)
            } else {
                weeklyRemaining = nil
            }

            // Check if data is stale (older than 10 minutes)
            let isStale = Date().timeIntervalSince(rateLimit.lastUpdated) > 600

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
