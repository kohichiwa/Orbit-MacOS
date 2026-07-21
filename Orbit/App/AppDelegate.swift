import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel: SpaceViewModel
    let settings: AppSettings
    private var statusBarController: StatusBarController?

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
        viewModel.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await viewModel.refresh() }
    }

    private func configureMainMenu(target: StatusBarController) {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Настройки…",
            action: #selector(StatusBarController.showSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = target
        applicationMenu.addItem(settingsItem)

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
