import AppKit

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class AppUpdater {
#if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController?
#endif

    init() {
#if canImport(Sparkle)
        updaterController = Self.hasSparkleConfiguration
            ? SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            : nil
#endif
    }

    func makeCheckForUpdatesMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: OrbitL10n.text(
                "menu.checkForUpdates",
                fallback: "Check for Updates..."
            ),
            action: nil,
            keyEquivalent: ""
        )

#if canImport(Sparkle)
        guard let updaterController else {
            item.isEnabled = false
            return item
        }
        item.target = updaterController
        item.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        return item
#else
        item.isEnabled = false
        return item
#endif
    }

#if canImport(Sparkle)
    private static var hasSparkleConfiguration: Bool {
        let bundle = Bundle.main
        return hasConfiguredValue(for: "SUFeedURL", in: bundle)
            && hasConfiguredValue(for: "SUPublicEDKey", in: bundle)
    }

    private static func hasConfiguredValue(
        for key: String,
        in bundle: Bundle
    ) -> Bool {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String
        else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("$(")
    }
#endif
}
