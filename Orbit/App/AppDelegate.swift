import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel: SpaceViewModel
    let settings: AppSettings
    private var statusBarController: StatusBarController?
    private var activationRefreshTask: Task<Void, Never>?

    override init() {
        let settings = AppSettings()
        self.settings = settings
        viewModel = SpaceViewModel(colorAssignments: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOlderOrbitInstances()
        NSApp.setActivationPolicy(.accessory)
        let statusBarController = StatusBarController(
            viewModel: viewModel,
            settings: settings
        )
        self.statusBarController = statusBarController
        configureMainMenu(target: statusBarController)
        viewModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        activationRefreshTask?.cancel()
        activationRefreshTask = nil
        statusBarController?.stop()
        statusBarController = nil
        viewModel.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activationRefreshTask?.cancel()
        activationRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await viewModel.refresh()
        }
    }

    private func configureMainMenu(target: StatusBarController) {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()

        let settingsItem = NSMenuItem(
            title: OrbitL10n.text(
                "menu.settings",
                fallback: "Settings…"
            ),
            action: #selector(StatusBarController.showSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = target
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: OrbitL10n.text(
                "menu.quit",
                fallback: "Quit Orbit"
            ),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = NSApp
        applicationMenu.addItem(quitItem)

        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        NSApp.mainMenu = mainMenu
    }

    private func terminateOlderOrbitInstances() {
        // Parallel XCTest workers launch multiple hosted Orbit processes with the
        // same bundle identifier. They must not terminate one another.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        where application.processIdentifier != ownProcessIdentifier {
            application.terminate()
        }
    }
}
