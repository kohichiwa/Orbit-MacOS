import AppKit
import CoreGraphics
import Foundation
import OSLog

private typealias OrbitCGSConnectionID = UInt32

@_silgen_name("_CGSDefaultConnection")
nonisolated private func orbitCGSDefaultConnection() -> OrbitCGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
nonisolated private func orbitCGSCopyManagedDisplaySpaces(
    _ connection: OrbitCGSConnectionID
) -> Unmanaged<CFArray>?

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

    nonisolated deinit {}

    func start(onChange: @escaping () -> Void) {
        stop()
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
                self?.changeHandler?()
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        changeHandler = nil
    }

    func read() async -> SpaceSnapshot? {
        let snapshot = await Task.detached(priority: .userInitiated) {
            Self.readFreshSnapshot()
        }.value
        if snapshot == nil {
            logger.error("The current macOS Spaces configuration could not be read")
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
            let rawDisplays = orbitCGSCopyManagedDisplaySpaces(
                orbitCGSDefaultConnection()
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
        guard !orderedIdentifiers.isEmpty, !desktopIdentifiers.isEmpty else { return nil }

        let activeIdentifier = (monitor["Current Space"] as? [String: Any]).flatMap(spaceIdentifier)
        return SpaceSnapshot(
            orderedIdentifiers: orderedIdentifiers,
            desktopIdentifiers: desktopIdentifiers,
            activeIdentifier: activeIdentifier
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
