import AppKit
import CoreGraphics
import Darwin
import Foundation
import OSLog

private typealias OrbitCGSConnectionID = UInt32
private typealias OrbitCGSDefaultConnectionFunction = @convention(c) () ->
    OrbitCGSConnectionID
private typealias OrbitCGSCopyManagedDisplaySpacesFunction = @convention(c) (
    OrbitCGSConnectionID
) -> Unmanaged<CFArray>?

private enum OrbitWindowServerSymbols {
    // These WindowServer entry points are private and may disappear in a future
    // macOS release. Resolve them lazily from AppKit's process image so Orbit can
    // continue with its preferences fallback instead of failing at launch.
    nonisolated static let defaultConnection = resolve(
        "_CGSDefaultConnection",
        as: OrbitCGSDefaultConnectionFunction.self
    )
    nonisolated static let copyManagedDisplaySpaces = resolve(
        "CGSCopyManagedDisplaySpaces",
        as: OrbitCGSCopyManagedDisplaySpacesFunction.self
    )

    nonisolated private static func resolve<Function>(
        _ name: String,
        as type: Function.Type
    ) -> Function? {
        let defaultSearchHandle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(defaultSearchHandle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }
}

@MainActor
protocol SpacesReading: AnyObject {
    func start(onChange: @escaping () -> Void)
    func stop()
    func read() async -> SpaceSnapshot?
}

/// A small best-effort adapter around the Spaces state maintained by macOS.
/// The live reader mirrors Spaceman's read-only approach. The preferences parser
/// remains a fallback when the live state cannot be decoded.
@MainActor
final class SystemSpacesReader: SpacesReading {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Orbit", category: "Spaces")
    private var observer: NSObjectProtocol?
    private var changeHandler: (() -> Void)?
    private var structureTimer: Timer?
    private var structureCheckTask: Task<Void, Never>?
    private var lastObservedIndicators: [SpaceIndicatorEntry]?
    private var isRunning = false
    private var lifecycleGeneration: UInt = 0
    private var hasLoggedReadFailure = false

    nonisolated deinit {}

    func start(onChange: @escaping () -> Void) {
        stop()
        isRunning = true
        let generation = lifecycleGeneration
        changeHandler = onChange
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            // The workspace notification center does not guarantee a concrete
            // sender for this notification. Filtering by `NSWorkspace.shared`
            // silently drops real Space changes on some macOS releases.
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard
                    let self,
                    self.isCurrentLifecycle(generation)
                else { return }
                self.changeHandler?()
            }
        }

        // Active-space notifications do not cover every Mission Control
        // structure change. This lightweight WindowServer check keeps
        // full-screen indicators in sync when an app enters or exits full screen.
        let structureTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard
                    let self,
                    self.isCurrentLifecycle(generation)
                else { return }
                self.checkSpaceStructure(generation: generation)
            }
        }
        structureTimer.tolerance = 0.1
        RunLoop.main.add(structureTimer, forMode: .common)
        self.structureTimer = structureTimer
        checkSpaceStructure(generation: generation)
    }

    func stop() {
        lifecycleGeneration &+= 1
        isRunning = false
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        structureTimer?.invalidate()
        structureTimer = nil
        structureCheckTask?.cancel()
        structureCheckTask = nil
        lastObservedIndicators = nil
        hasLoggedReadFailure = false
        changeHandler = nil
    }

    private func checkSpaceStructure(generation: UInt) {
        guard
            isCurrentLifecycle(generation),
            structureCheckTask == nil
        else { return }
        structureCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentLifecycle(generation) {
                    self.structureCheckTask = nil
                }
            }
            guard
                self.isCurrentLifecycle(generation),
                !Task.isCancelled,
                let snapshot = await self.read(priority: .utility),
                self.isCurrentLifecycle(generation),
                !Task.isCancelled
            else { return }

            let currentIndicators = snapshot.indicators
            defer { self.lastObservedIndicators = currentIndicators }
            guard
                let previousIndicators = self.lastObservedIndicators,
                previousIndicators != currentIndicators
            else { return }
            self.changeHandler?()
        }
    }

    private func isCurrentLifecycle(_ generation: UInt) -> Bool {
        isRunning && lifecycleGeneration == generation
    }

    func read() async -> SpaceSnapshot? {
        await read(priority: .userInitiated)
    }

    private func read(priority: TaskPriority) async -> SpaceSnapshot? {
        let snapshot = await Task.detached(priority: priority) {
            Self.readFreshSnapshot()
        }.value
        if snapshot == nil {
            if !hasLoggedReadFailure {
                logger.error(
                    "The current macOS Spaces configuration could not be read"
                )
                hasLoggedReadFailure = true
            }
        } else {
            hasLoggedReadFailure = false
        }
        return snapshot
    }

    nonisolated private static func readFreshSnapshot() -> SpaceSnapshot? {
        readManagedDisplaySnapshot() ?? readPreferencesSnapshot()
    }

    /// WindowServer is the only source that updates Current Space synchronously.
    /// `defaults export` can lag behind by several transitions on recent macOS.
    nonisolated private static func readManagedDisplaySnapshot() -> SpaceSnapshot? {
        guard
            let defaultConnection = OrbitWindowServerSymbols.defaultConnection,
            let copyManagedDisplaySpaces = OrbitWindowServerSymbols.copyManagedDisplaySpaces,
            let rawDisplays = copyManagedDisplaySpaces(
                defaultConnection()
            )?.takeRetainedValue(),
            let monitors = rawDisplays as? [[String: Any]]
        else { return nil }

        return decode(monitors: monitors)
    }

    nonisolated private static func readPreferencesSnapshot() -> SpaceSnapshot? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["export", "com.apple.spaces", "-"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard
                let root = plist as? [String: Any],
                let configuration = root["SpacesDisplayConfiguration"]
            else { return nil }
            return decode(configuration: configuration)
        } catch {
            return nil
        }
    }

    nonisolated static func decode(configuration: Any) -> SpaceSnapshot? {
        guard
            let root = configuration as? [String: Any],
            let management = root["Management Data"] as? [String: Any],
            let monitors = management["Monitors"] as? [[String: Any]]
        else { return nil }

        return decode(monitors: monitors)
    }

    nonisolated private static func decode(monitors: [[String: Any]]) -> SpaceSnapshot? {
        guard
            let monitor = mainMonitor(from: monitors),
            let rawSpaces = monitor["Spaces"] as? [[String: Any]]
        else { return nil }

        let entries: [(identifier: Int64, isDesktop: Bool)] = rawSpaces.compactMap { space in
            guard let identifier = spaceIdentifier(space) else { return nil }
            let type = (space["type"] as? NSNumber)?.intValue ?? 0
            let isFullscreen = space["TileLayoutManager"] != nil || type == 4
            return (identifier, type == 0 && !isFullscreen)
        }
        let orderedIdentifiers = entries.map(\.identifier)
        let desktopIdentifiers = entries.filter(\.isDesktop).map(\.identifier)
        var desktopColorIndex = 0
        let indicatorKinds: [SpaceIndicatorKind] = entries.map { entry in
            guard entry.isDesktop else {
                return .fullscreen(colorIndex: max(desktopColorIndex - 1, 0))
            }
            defer { desktopColorIndex += 1 }
            return .desktop(colorIndex: desktopColorIndex)
        }
        guard !orderedIdentifiers.isEmpty, !desktopIdentifiers.isEmpty else { return nil }

        let activeIdentifier = (monitor["Current Space"] as? [String: Any]).flatMap(spaceIdentifier)
        return SpaceSnapshot(
            orderedIdentifiers: orderedIdentifiers,
            desktopIdentifiers: desktopIdentifiers,
            activeIdentifier: activeIdentifier,
            indicatorKinds: indicatorKinds
        )
    }

    nonisolated private static func mainMonitor(
        from monitors: [[String: Any]]
    ) -> [String: Any]? {
        if let namedMain = monitors.first(where: {
            ($0["Display Identifier"] as? String) == "Main"
        }) {
            return namedMain
        }

        let mainDisplayID = CGMainDisplayID()
        if let physicalMain = monitors.first(where: { monitor in
            guard
                let identifier = monitor["Display Identifier"] as? String,
                let uuid = CFUUIDCreateFromString(nil, identifier as CFString)
            else { return false }
            return CGDisplayGetDisplayIDFromUUID(uuid) == mainDisplayID
        }) {
            return physicalMain
        }

        return monitors.first
    }

    nonisolated private static func spaceIdentifier(_ dictionary: [String: Any]) -> Int64? {
        if let value = dictionary["ManagedSpaceID"] as? NSNumber { return value.int64Value }
        if let value = dictionary["id64"] as? NSNumber { return value.int64Value }
        if let value = dictionary["id"] as? NSNumber { return value.int64Value }
        return nil
    }
}
