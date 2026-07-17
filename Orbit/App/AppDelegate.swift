import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = SpaceViewModel()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOlderOrbitInstances()
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(viewModel: viewModel)
        viewModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await viewModel.refresh() }
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
