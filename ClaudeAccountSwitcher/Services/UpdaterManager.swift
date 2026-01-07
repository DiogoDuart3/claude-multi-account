import Foundation
import Sparkle

/// Manages app auto-updates using Sparkle framework
/// Checks for updates from GitHub releases via an appcast.xml feed
final class UpdaterManager: ObservableObject {
    /// Shared singleton instance
    static let shared = UpdaterManager()
    
    /// The Sparkle updater controller
    private let updaterController: SPUStandardUpdaterController
    
    /// Access the underlying updater for configuration
    var updater: SPUUpdater {
        updaterController.updater
    }
    
    /// Whether the app can check for updates (used for UI state)
    @Published var canCheckForUpdates = false
    
    private init() {
        // Create the updater controller
        // - startingUpdater: true = start checking immediately
        // - updaterDelegate: nil = use default behavior
        // - userDriverDelegate: nil = use default UI
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        // Observe canCheckForUpdates property
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
    
    /// Manually check for updates (user-initiated)
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
    
    /// Get the current app version
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
    
    /// Get the current build number
    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
}
