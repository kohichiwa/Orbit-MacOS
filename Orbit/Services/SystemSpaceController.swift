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
            "Для переключения рабочих столов разрешите Orbit управление компьютером."
        case .eventCreationFailed:
            "Не удалось отправить системную команду переключения."
        case .automationPermissionRequired:
            "Разрешите Orbit управлять System Events в разделе «Автоматизация» системных настроек."
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

        let keyCode = direction.keyCode
        let failure: ScriptFailure? = await Task.detached(priority: .userInitiated) {
            () -> ScriptFailure? in
            let source = "tell application \"System Events\" to key code "
                + "\(keyCode) using {control down}"
            guard let script = NSAppleScript(source: source) else {
                return ScriptFailure(code: 0)
            }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            guard let error else { return nil }
            return ScriptFailure(
                code: error[NSAppleScript.errorNumber] as? Int ?? 0
            )
        }.value

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
