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

    private var percentLeft: Double {
        max(0, min(100, 100 - percentUsed))
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

        guard remaining > 0 else { return "Resets now" }

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
                    if let rateLimit = account.cachedRateLimit,
                       let remaining = rateLimit.sessionRemaining {
                        Text("\(remaining)% left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                
                // Delete button on hover
                if isHovered {
                    Button {
                        showDeleteConfirmation()
                    } label: {
                        Image(systemName: "trash")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
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
        }
        .buttonStyle(.plain)
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
}

// MARK: - Actions Section

struct ActionsSectionView: View {
    @EnvironmentObject var switcher: AccountSwitcher

    var body: some View {
        VStack(spacing: 0) {
            MenuActionButton(icon: "plus.circle", title: "Add Account...") {
                showAddAccountDialog()
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

// MARK: - Meta Section (Quit, etc.)

struct MetaSectionView: View {
    var body: some View {
        VStack(spacing: 0) {
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

// MARK: - Icon Renderer

/// Renders menu bar icons similar to CodexBar's style
enum IconRenderer {
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
            let trackFillAlpha: CGFloat = stale ? 0.18 : 0.28
            let trackStrokeAlpha: CGFloat = stale ? 0.28 : 0.44
            let fillColor = baseFill.withAlphaComponent(stale ? 0.55 : 1.0)

            let barWidthPx = 30 // 15 pt at 2×
            let barXPx = (canvasPx - barWidthPx) / 2

            func drawBar(rectPx: RectPx, remaining: Double?, alpha: CGFloat = 1.0, addClaudeStyle: Bool = false) {
                let rect = rectPx.rect()
                let cornerRadiusPx = addClaudeStyle ? 0 : rectPx.h / 2
                let radius = grid.pt(cornerRadiusPx)

                // Track background
                let trackPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
                baseFill.withAlphaComponent(trackFillAlpha * alpha).setFill()
                trackPath.fill()

                // Stroke outline
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

                // Fill based on remaining percentage
                if let remaining {
                    let clamped = max(0, min(remaining / 100, 1))
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

                // Claude-style critter decorations
                if addClaudeStyle {
                    let ctx = NSGraphicsContext.current?.cgContext
                    fillColor.withAlphaComponent(alpha).setFill()

                    // Arms/claws
                    let armWidthPx = 3
                    let armHeightPx = max(0, rectPx.h - 6)
                    let armYPx = rectPx.y + 3
                    let leftArm = grid.rect(x: rectPx.x - armWidthPx, y: armYPx, w: armWidthPx, h: armHeightPx)
                    let rightArm = grid.rect(x: rectPx.x + rectPx.w, y: armYPx, w: armWidthPx, h: armHeightPx)
                    NSBezierPath(rect: leftArm).fill()
                    NSBezierPath(rect: rightArm).fill()

                    // Legs
                    let legCount = 4
                    let legWidthPx = 2
                    let legHeightPx = 3
                    let legYPx = rectPx.y - legHeightPx
                    let stepPx = max(1, rectPx.w / (legCount + 1))
                    for idx in 0..<legCount {
                        let cx = rectPx.x + stepPx * (idx + 1)
                        let leg = grid.rect(x: cx - legWidthPx / 2, y: legYPx, w: legWidthPx, h: legHeightPx)
                        NSBezierPath(rect: leg).fill()
                    }

                    // Eyes
                    let eyeWidthPx = 2
                    let eyeHeightPx = 5
                    let eyeOffsetPx = 6
                    let eyeYPx = rectPx.y + rectPx.h - eyeHeightPx - 2
                    ctx?.saveGState()
                    ctx?.setShouldAntialias(false)
                    ctx?.clear(grid.rect(
                        x: rectPx.midXPx - eyeOffsetPx - eyeWidthPx / 2,
                        y: eyeYPx,
                        w: eyeWidthPx,
                        h: eyeHeightPx))
                    ctx?.clear(grid.rect(
                        x: rectPx.midXPx + eyeOffsetPx - eyeWidthPx / 2,
                        y: eyeYPx,
                        w: eyeWidthPx,
                        h: eyeHeightPx))
                    ctx?.restoreGState()
                }
            }

            // Top bar (session) - larger, with Claude style
            let topRectPx = RectPx(x: barXPx, y: 19, w: barWidthPx, h: 12)
            // Bottom bar (weekly) - smaller
            let bottomRectPx = RectPx(x: barXPx, y: 5, w: barWidthPx, h: 8)

            drawBar(rectPx: topRectPx, remaining: sessionRemaining, addClaudeStyle: true)

            if weeklyRemaining != nil {
                drawBar(rectPx: bottomRectPx, remaining: weeklyRemaining)
            } else {
                drawBar(rectPx: bottomRectPx, remaining: nil, alpha: 0.45)
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
