import AppKit
import SwiftUI

// MARK: - Menu Highlight Style

private struct MenuItemHighlightedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var menuItemHighlighted: Bool {
        get { self[MenuItemHighlightedKey.self] }
        set { self[MenuItemHighlightedKey.self] = newValue }
    }
}

enum MenuHighlightStyle {
    static let selectionText = Color(nsColor: .selectedMenuItemTextColor)
    static let normalPrimaryText = Color(nsColor: .controlTextColor)
    static let normalSecondaryText = Color(nsColor: .secondaryLabelColor)

    static func primary(_ highlighted: Bool) -> Color {
        highlighted ? selectionText : normalPrimaryText
    }

    static func secondary(_ highlighted: Bool) -> Color {
        highlighted ? selectionText : normalSecondaryText
    }

    static func error(_ highlighted: Bool) -> Color {
        highlighted ? selectionText : Color(nsColor: .systemRed)
    }

    static func progressTrack(_ highlighted: Bool) -> Color {
        highlighted ? selectionText.opacity(0.22) : Color(nsColor: .tertiaryLabelColor).opacity(0.22)
    }

    static func progressTint(_ highlighted: Bool, fallback: Color) -> Color {
        highlighted ? selectionText : fallback
    }

    static func selectionBackground(_ highlighted: Bool) -> Color {
        highlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear
    }
}

// MARK: - Main Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var switcher: AccountSwitcher

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Active account usage card
            if let active = switcher.activeAccount {
                UsageMenuCardView(account: active)
            } else {
                // No active account placeholder
                NoAccountPlaceholderView()
            }

            // Other accounts section (if any)
            let inactiveAccounts = switcher.accounts.filter { !$0.isActive }
            if !inactiveAccounts.isEmpty {
                Divider()
                    .padding(.horizontal, 10)

                OtherAccountsSectionView(accounts: inactiveAccounts)
            }

            Divider()
                .padding(.horizontal, 10)

            // Actions section
            ActionsSectionView()

            Divider()
                .padding(.horizontal, 10)

            // Meta section (Quit)
            MetaSectionView()
        }
        .frame(width: 310)
    }
}

// MARK: - No Account Placeholder

struct NoAccountPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No account configured")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
}

// MARK: - Usage Menu Card (Main Card)

struct UsageMenuCardView: View {
    let account: Account
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Section
            UsageCardHeaderView(account: account)

            if account.cachedRateLimit != nil {
                Divider()

                // Usage Metrics Section
                UsageMetricsSectionView(account: account)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(alignment: .topLeading) {
            if isHovered {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MenuHighlightStyle.selectionBackground(true))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
        }
        .foregroundStyle(MenuHighlightStyle.primary(isHovered))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Usage Card Header

struct UsageCardHeaderView: View {
    let account: Account
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Claude Code")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text(account.name)
                    .font(.subheadline)
                    .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
            }
            HStack(alignment: .firstTextBaseline) {
                if let rateLimit = account.cachedRateLimit {
                    Text(formatLastUpdated(rateLimit.lastUpdated))
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                } else {
                    Text("Not fetched yet")
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                }
                Spacer()
                if let rateLimit = account.cachedRateLimit, let plan = planText(from: rateLimit) {
                    Text(plan)
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                }
            }
        }
    }

    private func formatLastUpdated(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Updated just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "Updated \(mins)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "Updated \(hours)h ago"
        }
    }

    private func planText(from rateLimit: RateLimitInfo) -> String? {
        // Extract plan info if available
        return nil
    }
}

// MARK: - Usage Metrics Section

struct UsageMetricsSectionView: View {
    let account: Account

    var body: some View {
        if let rateLimit = account.cachedRateLimit {
            VStack(alignment: .leading, spacing: 12) {
                // Session usage
                if let sessionUsed = rateLimit.sessionUsed, rateLimit.sessionLimit != nil {
                    UsageProgressMetricView(
                        title: "Session",
                        percentUsed: Double(sessionUsed),
                        resetTime: rateLimit.resetTime
                    )
                }

                // Weekly usage
                if let weeklyUsed = rateLimit.weeklyUsed, rateLimit.weeklyLimit != nil {
                    UsageProgressMetricView(
                        title: "Weekly",
                        percentUsed: Double(weeklyUsed),
                        resetTime: rateLimit.weeklyResetTime,
                        paceInfo: calculatePace(
                            percentUsed: Double(weeklyUsed),
                            resetTime: rateLimit.weeklyResetTime
                        )
                    )
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func calculatePace(percentUsed: Double, resetTime: Date?) -> String? {
        guard let resetTime = resetTime else { return nil }

        let now = Date()
        let totalWeekSeconds: Double = 7 * 24 * 60 * 60
        let remainingSeconds = resetTime.timeIntervalSince(now)
        let elapsedSeconds = totalWeekSeconds - remainingSeconds

        guard elapsedSeconds > 0 else { return nil }

        let expectedUsagePercent = elapsedSeconds / totalWeekSeconds
        let actualUsagePercent = percentUsed / 100
        let paceDiff = (actualUsagePercent - expectedUsagePercent) * 100

        let status: String
        if paceDiff > 5 {
            status = "Ahead (+\(Int(paceDiff))%)"
        } else if paceDiff < -5 {
            status = "Behind (\(Int(paceDiff))%)"
        } else {
            status = "On track"
        }

        let usageRate = actualUsagePercent / elapsedSeconds
        let projectedTotal = usageRate * totalWeekSeconds * 100
        let projection: String
        if projectedTotal <= 100 {
            projection = "Lasts to reset"
        } else {
            projection = "May run out early"
        }

        return "Pace: \(status) · \(projection)"
    }
}

// MARK: - Usage Progress Metric View

struct UsageProgressMetricView: View {
    let title: String
    let percentUsed: Double
    let resetTime: Date?
    var paceInfo: String? = nil

    @Environment(\.menuItemHighlighted) private var isHighlighted

    /// Returns true if the reset time has passed, meaning the limit should be reset to 100%
    private var hasReset: Bool {
        guard let reset = resetTime else { return false }
        return reset <= Date()
    }

    private var percentLeft: Double {
        // If reset time has passed, show 100% remaining
        if hasReset {
            return 100
        }
        return max(0, min(100, 100 - percentUsed))
    }

    private var progressColor: Color {
        if percentLeft <= 10 {
            return Color(nsColor: .systemRed)
        } else if percentLeft <= 30 {
            return Color(nsColor: .systemOrange)
        } else {
            return Color(red: 0.45, green: 0.75, blue: 0.45)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body)
                .fontWeight(.medium)

            // Progress bar
            UsageProgressBar(
                percent: percentLeft,
                tint: progressColor
            )

            // Labels row
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(percentLeft))% left")
                    .font(.footnote)
                Spacer()
                if let reset = resetTime {
                    Text(formatResetTime(reset))
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                }
            }

            // Pace info for weekly
            if let pace = paceInfo {
                Text(pace)
                    .font(.footnote)
                    .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                    .lineLimit(1)
            }
        }
    }

    private func formatResetTime(_ date: Date) -> String {
        let now = Date()
        let remaining = date.timeIntervalSince(now)

        guard remaining > 0 else { return "Just reset" }

        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if days > 0 {
            return "Resets in \(days)d \(hours)h"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }
}

// MARK: - Usage Progress Bar

struct UsageProgressBar: View {
    let percent: Double
    let tint: Color

    @Environment(\.menuItemHighlighted) private var isHighlighted

    private var clampedPercent: Double {
        min(100, max(0, percent))
    }

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = proxy.size.width * (clampedPercent / 100)
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(MenuHighlightStyle.progressTrack(isHighlighted))
                // Fill
                Capsule()
                    .fill(MenuHighlightStyle.progressTint(isHighlighted, fallback: tint))
                    .frame(width: max(0, fillWidth))
            }
        }
        .frame(height: 6)
        .accessibilityValue("\(Int(clampedPercent)) percent remaining")
    }
}

// MARK: - Other Accounts Section

struct OtherAccountsSectionView: View {
    let accounts: [Account]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Other Accounts")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ForEach(accounts) { account in
                AccountSwitchRow(account: account)
            }
        }
    }
}

// MARK: - Account Switch Row

struct AccountSwitchRow: View {
    let account: Account
    @EnvironmentObject var switcher: AccountSwitcher
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task { await switcher.switchTo(account: account) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.circle")
                        .imageScale(.medium)
                        .frame(width: 18, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .font(.body)
                        if let rateLimit = account.cachedRateLimit {
                            HStack(spacing: 8) {
                                if let sessionUsed = rateLimit.sessionUsed {
                                    // Show 100% if the session reset time has passed
                                    let sessionHasReset = rateLimit.resetTime.map { $0 <= Date() } ?? false
                                    let sessionLeft = sessionHasReset ? 100 : max(0, 100 - sessionUsed)
                                    Text("Session: \(sessionLeft)%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let weeklyUsed = rateLimit.weeklyUsed {
                                    // Show 100% if the weekly reset time has passed
                                    let weeklyHasReset = rateLimit.weeklyResetTime.map { $0 <= Date() } ?? false
                                    let weeklyLeft = weeklyHasReset ? 100 : max(0, 100 - weeklyUsed)
                                    Text("Weekly: \(weeklyLeft)%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let resetTime = rateLimit.resetTime {
                                Text(formatResetTime(resetTime))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isHovered {
                Button {
                    showDeleteConfirmation()
                } label: {
                    Image(systemName: "trash")
                        .imageScale(.small)
                        .foregroundStyle(isHovered ? MenuHighlightStyle.secondary(true) : .secondary)
                }
                .buttonStyle(.plain)
                .help("Remove account")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? MenuHighlightStyle.selectionBackground(true) : .clear)
                .padding(.horizontal, 6)
        )
        .foregroundStyle(MenuHighlightStyle.primary(isHovered))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
    
    private func showDeleteConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Remove Account"
        alert.informativeText = "Are you sure you want to remove \"\(account.name)\"? This will delete all saved data for this account."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        
        // Make the Remove button destructive (red)
        if let removeButton = alert.buttons.first {
            removeButton.hasDestructiveAction = true
        }
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            switcher.removeAccount(account)
        }
    }
    
    private func formatResetTime(_ date: Date) -> String {
        let now = Date()
        let remaining = date.timeIntervalSince(now)
        
        guard remaining > 0 else { return "Just reset" }
        
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        
        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }
}

// MARK: - Actions Section

struct ActionsSectionView: View {
    @EnvironmentObject var switcher: AccountSwitcher

    var body: some View {
        VStack(spacing: 0) {
            MenuActionButton(icon: "plus.circle", title: "Add Account...") {
                showAddAccountDialog()
            }
            
            MenuActionButton(icon: "gearshape", title: "Manage Accounts...") {
                ManageAccountsWindowController.shared.showWindow(switcher: switcher)
            }

            MenuActionButton(icon: "arrow.clockwise", title: "Refresh") {
                Task { await switcher.refreshAllAccounts() }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func showAddAccountDialog() {
        // Create an alert to get account name
        let alert = NSAlert()
        alert.messageText = "Add New Account"
        alert.informativeText = "Enter a name for this account. After clicking Add, Terminal will open to complete the Claude login."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Add Account")
        alert.addButton(withTitle: "Cancel")
        
        // Add text field for account name
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.placeholderString = "e.g., Work, Personal, Client Project"
        textField.stringValue = ""
        alert.accessoryView = textField
        
        // Make the text field first responder
        alert.window.initialFirstResponder = textField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let accountName = textField.stringValue.isEmpty ? "New Account" : textField.stringValue
            Task {
                await switcher.addAccount(name: accountName)
            }
        }
    }
}

// MARK: - Meta Section (Quit, Updates, etc.)

struct MetaSectionView: View {
    @ObservedObject private var updaterManager = UpdaterManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            MenuActionButton(icon: "arrow.down.circle", title: "Check for Updates...") {
                updaterManager.checkForUpdates()
            }
            .disabled(!updaterManager.canCheckForUpdates)
            
            MenuActionButton(icon: "power", title: "Quit", shortcut: "Q") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Menu Action Button

struct MenuActionButton: View {
    let icon: String
    let title: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .imageScale(.medium)
                    .frame(width: 18, alignment: .center)
                Text(title)
                Spacer()
                if let shortcut = shortcut {
                    Text("⌘\(shortcut)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(MenuHighlightStyle.primary(isHovered))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? MenuHighlightStyle.selectionBackground(true) : .clear)
                .padding(.horizontal, 6)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Icon Renderer (matches CodexBar exactly)

enum IconRenderer {
    // Render to an 18×18 pt template (36×36 px at 2×) to match the system menu bar size.
    private static let outputSize = NSSize(width: 18, height: 18)
    private static let outputScale: CGFloat = 2
    private static let canvasPx = Int(outputSize.width * outputScale) // 36px

    private struct PixelGrid {
        let scale: CGFloat

        func pt(_ px: Int) -> CGFloat {
            CGFloat(px) / scale
        }

        func rect(x: Int, y: Int, w: Int, h: Int) -> CGRect {
            CGRect(x: pt(x), y: pt(y), width: pt(w), height: pt(h))
        }
    }

    private static let grid = PixelGrid(scale: outputScale)

    private struct RectPx {
        let x: Int
        let y: Int
        let w: Int
        let h: Int

        var midXPx: Int { x + w / 2 }
        var midYPx: Int { y + h / 2 }

        func rect() -> CGRect {
            IconRenderer.grid.rect(x: x, y: y, w: w, h: h)
        }
    }

    /// Creates a menu bar icon showing session and weekly usage
    static func makeIcon(
        sessionRemaining: Double?,
        weeklyRemaining: Double?,
        stale: Bool = false
    ) -> NSImage {
        renderImage {
            let baseFill = NSColor.labelColor
            // Reduced opacity to ensure empty bars don't look "filled"
            let trackFillAlpha: CGFloat = stale ? 0.12 : 0.15 
            let trackStrokeAlpha: CGFloat = stale ? 0.20 : 0.30
            let fillColor = baseFill.withAlphaComponent(stale ? 0.55 : 1.0)

            let barWidthPx = 30 // 15 pt at 2×
            let barXPx = (canvasPx - barWidthPx) / 2

            func drawBar(
                rectPx: RectPx,
                remaining: Double?,
                alpha: CGFloat = 1.0,
                // Change default to false to use cleaner capsule style
                addNotches: Bool = false 
            ) {
                let rect = rectPx.rect()
                // Use rounded corners (capsule) for cleaner look
                let cornerRadiusPx = addNotches ? 0 : rectPx.h / 2
                let radius = grid.pt(cornerRadiusPx)

                // Track background
                let trackPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
                baseFill.withAlphaComponent(trackFillAlpha * alpha).setFill()
                trackPath.fill()

                // Stroke outline - simpler stroke for better scaling
                let strokeWidthPx = 2
                let insetPx = strokeWidthPx / 2
                let strokeRect = grid.rect(
                    x: rectPx.x + insetPx,
                    y: rectPx.y + insetPx,
                    w: max(0, rectPx.w - insetPx * 2),
                    h: max(0, rectPx.h - insetPx * 2))
                let strokePath = NSBezierPath(
                    roundedRect: strokeRect,
                    xRadius: grid.pt(max(0, cornerRadiusPx - insetPx)),
                    yRadius: grid.pt(max(0, cornerRadiusPx - insetPx)))
                strokePath.lineWidth = CGFloat(strokeWidthPx) / outputScale
                baseFill.withAlphaComponent(trackStrokeAlpha * alpha).setStroke()
                strokePath.stroke()

                // Fill: clip to the capsule and paint a left-to-right rect so the progress edge is straight.
                if let remaining {
                    // remaining is 0..100
                    let clamped = max(0, min(remaining / 100.0, 1.0))
                    let fillWidthPx = max(0, min(rectPx.w, Int((CGFloat(rectPx.w) * CGFloat(clamped)).rounded())))
                    
                    if fillWidthPx > 0 {
                        NSGraphicsContext.current?.cgContext.saveGState()
                        trackPath.addClip()
                        fillColor.withAlphaComponent(alpha).setFill()
                        NSBezierPath(
                            rect: grid.rect(
                                x: rectPx.x,
                                y: rectPx.y,
                                w: fillWidthPx,
                                h: rectPx.h)).fill()
                        NSGraphicsContext.current?.cgContext.restoreGState()
                    }
                }
                
                // Note: "Notches" (critter style) removed from usage to provide cleaner look
            }

            let topValue = sessionRemaining
            let bottomValue = weeklyRemaining

            let hasWeekly = (weeklyRemaining != nil)
            let weeklyAvailable = hasWeekly && (weeklyRemaining ?? 0) > 0
            
            // Top bar (session)
            let topRectPx = RectPx(x: barXPx, y: 19, w: barWidthPx, h: 12)
            // Bottom bar (weekly)
            let bottomRectPx = RectPx(x: barXPx, y: 5, w: barWidthPx, h: 8)

            if weeklyAvailable {
                // Normal: top=session, bottom=weekly
                // Changed addNotches to false for cleaner capsule look
                drawBar(rectPx: topRectPx, remaining: topValue, addNotches: false)
                drawBar(rectPx: bottomRectPx, remaining: bottomValue)
            } else if !hasWeekly {
                // Weekly missing: dim bottom
                drawBar(rectPx: topRectPx, remaining: topValue, addNotches: false)
                drawBar(rectPx: bottomRectPx, remaining: nil, alpha: 0.45)
            } else {
                // Weekly exhausted
                drawBar(rectPx: topRectPx, remaining: topValue, addNotches: false)
                drawBar(rectPx: bottomRectPx, remaining: bottomValue)
            }
        }
    }

    private static func renderImage(_ draw: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: outputSize, flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }
}
