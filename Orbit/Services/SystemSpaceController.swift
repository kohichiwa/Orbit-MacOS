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

    var keyCode: Int { self == .previous ? 123 : 124 }
}

enum SystemSpaceControllerError: LocalizedError {
    case eventPostingPermissionRequired
    case eventCreationFailed
    case automationPermissionRequired

    var errorDescription: String? {
        switch self {
        case .eventPostingPermissionRequired:
            OrbitL10n.text(
                "error.accessibility.permissionRequired",
                fallback: "Allow Orbit to control your computer to switch desktops."
            )
        case .eventCreationFailed:
            OrbitL10n.text(
                "error.spaceSwitch.commandFailed",
                fallback: "Couldn't send the system command to switch desktops."
            )
        case .automationPermissionRequired:
            OrbitL10n.text(
                "error.automation.permissionRequired",
                fallback: "Allow Orbit to control System Events in the Automation section of System Settings."
            )
        }
    }
}

@MainActor
final class SystemSpaceController: SpaceControlling {
    nonisolated deinit {}

    /// The check never presents a prompt. Permission is requested only from the
    /// explicit context-menu action, never from a dot click.
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
        guard canPostEvents else {
            throw SystemSpaceControllerError.eventPostingPermissionRequired
        }

        // NSAppleScript is explicitly main-thread-only. This controller is
        // MainActor-isolated, so keep both construction and execution here.
        let source = "tell application \"System Events\" to key code "
            + "\(direction.keyCode) using {control down}"
        guard let script = NSAppleScript(source: source) else {
            throw SystemSpaceControllerError.eventCreationFailed
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        let failure = error.map {
            ScriptFailure(code: $0[NSAppleScript.errorNumber] as? Int ?? 0)
        }

        guard let failure else { return }
        if abs(failure.code) == 1743 {
            throw SystemSpaceControllerError.automationPermissionRequired
        }
        if abs(failure.code) == 1002 {
            throw SystemSpaceControllerError.eventPostingPermissionRequired
        }
        throw SystemSpaceControllerError.eventCreationFailed
    }
}

private struct ScriptFailure: Sendable {
    let code: Int
}
