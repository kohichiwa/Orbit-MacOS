import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol SpaceControlling: AnyObject {
    var canPostEvents: Bool { get }
    @discardableResult func requestAccessibilityPermission() -> Bool
    func move(_ direction: SpaceDirection) async throws
}

enum SpaceDirection: Equatable, Sendable {
    case previous
    case next
}

enum SystemSpaceControllerError: LocalizedError {
    case eventPostingPermissionRequired
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .eventPostingPermissionRequired:
            L10n.string("error.accessibility.required")
        case .eventCreationFailed:
            L10n.string("error.command.failed")
        }
    }
}

@MainActor
final class SystemSpaceController: SpaceControlling {
    // Dock-swipe event fields used by macOS for native Space navigation.
    // This is the same three-phase mechanism used by Spaceman's
    // GestureSwitcher (began -> changed -> ended).
    private static let eventTypeField = CGEventField(rawValue: 55)!
    private static let gestureHIDType = CGEventField(rawValue: 110)!
    private static let swipeMotion = CGEventField(rawValue: 123)!
    private static let swipeProgress = CGEventField(rawValue: 124)!
    private static let swipePositionX = CGEventField(rawValue: 125)!
    private static let swipeVelocityX = CGEventField(rawValue: 129)!
    private static let swipeVelocityY = CGEventField(rawValue: 130)!
    private static let gesturePhase = CGEventField(rawValue: 132)!
    private static let gesturePhase2 = CGEventField(rawValue: 134)!
    private static let gestureFlavor = CGEventField(rawValue: 138)!
    private static let eventTimestamp = CGEventField(rawValue: 169)!

    private static let phaseBegan: Int64 = 1
    private static let phaseChanged: Int64 = 2
    private static let phaseEnded: Int64 = 4
    private static let gestureVelocity = 10.0

    nonisolated deinit {}

    /// This state is used only to describe the permission in the settings menu.
    var canPostEvents: Bool { AXIsProcessTrusted() }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        guard !canPostEvents else { return true }
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func move(_ direction: SpaceDirection) async throws {
        let goRight = direction == .next
        for phase in [Self.phaseBegan, Self.phaseChanged, Self.phaseEnded] {
            try postDockSwipe(
                phase: phase,
                goRight: goRight,
                velocity: Self.gestureVelocity
            )
        }
    }

    private func postDockSwipe(
        phase: Int64,
        goRight: Bool,
        velocity: Double
    ) throws {
        guard let event = CGEvent(source: nil) else {
            throw SystemSpaceControllerError.eventCreationFailed
        }

        let progress = goRight ? 1.0 : -1.0
        let horizontalVelocity = goRight ? velocity : -velocity

        event.setIntegerValueField(Self.eventTypeField, value: 30)
        event.setIntegerValueField(Self.gestureHIDType, value: 23)
        event.setIntegerValueField(Self.gesturePhase, value: phase)
        event.setDoubleValueField(Self.swipeProgress, value: progress)
        event.setIntegerValueField(Self.swipeMotion, value: 1)
        event.setDoubleValueField(
            Self.swipeVelocityX,
            value: horizontalVelocity
        )
        event.setDoubleValueField(Self.swipeVelocityY, value: 0)

        event.setIntegerValueField(Self.gesturePhase2, value: phase)
        event.setDoubleValueField(Self.gestureFlavor, value: 3)
        event.setDoubleValueField(
            Self.eventTimestamp,
            value: Double(mach_absolute_time())
        )
        event.setDoubleValueField(Self.swipePositionX, value: 0.1)

        event.post(tap: .cgSessionEventTap)
    }
}
