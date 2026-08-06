import CoreGraphics
import Darwin
import Foundation

private typealias OrbitApplicationCGSConnectionID = UInt32
private typealias OrbitApplicationCGSDefaultConnectionFunction =
    @convention(c) () -> OrbitApplicationCGSConnectionID
private typealias OrbitCGSCopyWindowsWithOptionsAndTagsFunction =
    @convention(c) (
        OrbitApplicationCGSConnectionID,
        UInt32,
        CFArray,
        UInt32,
        UnsafeMutablePointer<UInt64>,
        UnsafeMutablePointer<UInt64>
    ) -> Unmanaged<CFArray>?
private enum OrbitSpaceWindowSymbols {
    nonisolated static let defaultConnection = resolve(
        "_CGSDefaultConnection",
        as: OrbitApplicationCGSDefaultConnectionFunction.self
    )
    nonisolated static let copyWindowsWithOptionsAndTags = resolve(
        "CGSCopyWindowsWithOptionsAndTags",
        as: OrbitCGSCopyWindowsWithOptionsAndTagsFunction.self
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

protocol SpaceApplicationReading: Sendable {
    func applicationProcessIdentifiers(in spaceIdentifier: Int64) async
        -> [pid_t]
}

/// Reads applications only when a user deliberately hovers a Space. There is
/// no timer or persistent window observer, so the feature has no idle cost.
final class SystemSpaceApplicationReader: SpaceApplicationReading,
    @unchecked Sendable {
    func applicationProcessIdentifiers(in spaceIdentifier: Int64) async
        -> [pid_t] {
        await Task.detached(priority: .userInitiated) {
            Self.readApplicationProcessIdentifiers(
                in: spaceIdentifier,
                excluding: ProcessInfo.processInfo.processIdentifier
            )
        }.value
    }

    nonisolated private static func readApplicationProcessIdentifiers(
        in spaceIdentifier: Int64,
        excluding ownProcessIdentifier: pid_t
    ) -> [pid_t] {
        guard
            spaceIdentifier > 0,
            let defaultConnection = OrbitSpaceWindowSymbols.defaultConnection,
            let copyWindows = OrbitSpaceWindowSymbols
                .copyWindowsWithOptionsAndTags
        else { return [] }

        let connection = defaultConnection()
        var setTags: UInt64 = 0
        // Exclude WindowServer-managed desktop elements while retaining normal
        // and minimized application windows assigned to the Space.
        var clearTags: UInt64 = 0x4000000000
        let spaces = [NSNumber(value: spaceIdentifier)] as CFArray
        guard let rawWindowIdentifiers = copyWindows(
            connection,
            0,
            spaces,
            2,
            &setTags,
            &clearTags
        )?.takeRetainedValue() as? [NSNumber] else { return [] }

        let windowIdentifiers = rawWindowIdentifiers.map(\.uint32Value)
        let applicationContentOwners =
            applicationContentOwnersByWindowIdentifier(
                windowIdentifiers: rawWindowIdentifiers
            )
        // `copyWindows` is already scoped to the requested Space. Re-checking
        // every window through a second WindowServer entry point is unreliable
        // on macOS 26 and can turn a valid result into an empty preview.
        return processIdentifiers(
            windowIdentifiers: windowIdentifiers,
            excluding: ownProcessIdentifier
        ) { windowIdentifier in
            return applicationContentOwners[windowIdentifier]
        }
    }

    /// WindowServer also returns menu-bar items and transient app-owned panels.
    /// A regular application can therefore appear in the active Space merely
    /// because its status item is visible there. Restricting the candidates to
    /// layer-zero, visible-sized content windows keeps the result tied to the
    /// application's actual windows instead of its process-wide UI helpers.
    nonisolated private static func applicationContentOwnersByWindowIdentifier(
        windowIdentifiers: [NSNumber]
    ) -> [CGWindowID: pid_t] {
        // Asking WindowServer for the descriptions of the exact CGS result is
        // important on macOS 26. A global window-list snapshot can omit an
        // off-Space full-screen window even though CGS returned its identifier.
        let exactWindowInformation = CGWindowListCreateDescriptionFromArray(
            windowIdentifiers as CFArray
        ) as? [[String: Any]]
        if let exactWindowInformation, !exactWindowInformation.isEmpty {
            return applicationContentOwners(
                from: exactWindowInformation
            )
        }

        guard
            let rawWindowInformation = CGWindowListCopyWindowInfo(
                [.optionAll],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return [:] }

        return applicationContentOwners(from: rawWindowInformation)
    }

    nonisolated static func applicationContentOwners(
        from windowInformation: [[String: Any]]
    ) -> [CGWindowID: pid_t] {
        var owners: [CGWindowID: pid_t] = [:]
        owners.reserveCapacity(windowInformation.count)
        for information in windowInformation {
            guard
                let windowNumber = information[
                    kCGWindowNumber as String
                ] as? NSNumber,
                let processIdentifier = information[
                    kCGWindowOwnerPID as String
                ] as? NSNumber,
                let layer = information[
                    kCGWindowLayer as String
                ] as? NSNumber,
                let alpha = information[
                    kCGWindowAlpha as String
                ] as? NSNumber,
                let boundsDictionary = information[
                    kCGWindowBounds as String
                ] as? NSDictionary,
                let bounds = CGRect(
                    dictionaryRepresentation:
                        boundsDictionary as CFDictionary
                ),
                isApplicationContentWindow(
                    layer: layer.intValue,
                    alpha: alpha.doubleValue,
                    bounds: bounds
                )
            else { continue }
            owners[windowNumber.uint32Value] =
                processIdentifier.int32Value
        }
        return owners
    }

    nonisolated static func isApplicationContentWindow(
        layer: Int,
        alpha: Double,
        bounds: CGRect
    ) -> Bool {
        layer == 0
            && alpha > 0.001
            && bounds.width > 1
            && bounds.height > 1
    }

    nonisolated static func processIdentifiers(
        windowIdentifiers: [CGWindowID],
        excluding ownProcessIdentifier: pid_t,
        processIdentifierForWindow: (CGWindowID) -> pid_t?
    ) -> [pid_t] {
        var seenProcessIdentifiers = Set<pid_t>()
        var processIdentifiers: [pid_t] = []
        for windowIdentifier in windowIdentifiers {
            guard let processIdentifier = processIdentifierForWindow(
                windowIdentifier
            ) else { continue }
            guard
                processIdentifier > 0,
                processIdentifier != ownProcessIdentifier,
                seenProcessIdentifiers.insert(processIdentifier).inserted
            else { continue }
            processIdentifiers.append(processIdentifier)
        }
        return processIdentifiers
    }
}
