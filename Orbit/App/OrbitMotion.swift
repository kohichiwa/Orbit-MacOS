import SwiftUI

/// Shared motion language for Orbit.
///
/// The presets intentionally use SwiftUI's system springs. They stay brief,
/// interruptible and consistent between the settings preview and AppKit-backed
/// status item while retaining only the motion that communicates state.
enum OrbitMotion {
    /// Apple HIG asks custom feedback motion to stay brief and optional.
    /// Every Orbit animation is routed through this policy so the in-app
    /// switch and the system Reduce Motion preference cannot drift apart.
    nonisolated static let maximumFeedbackDuration: TimeInterval = 0.50
    nonisolated static let seamlessDuration: TimeInterval = 0.42
    nonisolated static let classicDuration: TimeInterval = 0.235
    nonisolated static let continuousDuration: TimeInterval = 0.46
    nonisolated static let hoverEnterDuration: TimeInterval = 0.22
    nonisolated static let hoverExitDuration: TimeInterval = 0.30
    nonisolated static let paletteDuration: TimeInterval = 0.28
    nonisolated static let colorDuration: TimeInterval = 0.20
    nonisolated static let pressDuration: TimeInterval = 0.10
    nonisolated static let selectionHoverDuration: TimeInterval = 0.14
    nonisolated static let selectionChangeDuration: TimeInterval = 0.18
    nonisolated static let reducedMotionFadeDuration: TimeInterval = 0.12
    nonisolated static let flowStretchDuration: TimeInterval = 0.08
    nonisolated static let flowSquashDuration: TimeInterval = 0.14
    nonisolated static let flowSettleDuration: TimeInterval = 0.16

    nonisolated static func allowsMotion(
        userEnabled: Bool,
        reduceMotion: Bool
    ) -> Bool {
        userEnabled && !reduceMotion
    }

    static func indicatorChange(
        style: IndicatorAnimationStyle,
        enabled: Bool,
        reduceMotion: Bool
    ) -> Animation? {
        guard allowsMotion(
            userEnabled: enabled,
            reduceMotion: reduceMotion
        ) else { return nil }
        switch style {
        case .seamless:
            return .smooth(duration: seamlessDuration, extraBounce: 0)
        case .classic:
            return .snappy(duration: classicDuration, extraBounce: 0)
        case .continuous:
            return .smooth(duration: continuousDuration, extraBounce: 0)
        }
    }

    static func hover(
        isHovered: Bool,
        enabled: Bool,
        reduceMotion: Bool
    ) -> Animation? {
        guard allowsMotion(
            userEnabled: enabled,
            reduceMotion: reduceMotion
        ) else { return nil }
        return isHovered
            ? .snappy(duration: hoverEnterDuration, extraBounce: 0)
            : .smooth(duration: hoverExitDuration, extraBounce: 0)
    }

    static func palette(
        enabled: Bool,
        reduceMotion: Bool
    ) -> Animation? {
        guard enabled else { return nil }
        if reduceMotion {
            return .easeOut(duration: reducedMotionFadeDuration)
        }
        return .snappy(duration: paletteDuration, extraBounce: 0)
    }

    static func selectionHover(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? nil
            : .easeOut(duration: selectionHoverDuration)
    }

    static func selectionChange(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? nil
            : .easeOut(duration: selectionChangeDuration)
    }

    static func colorChange(
        enabled: Bool,
        reduceMotion: Bool
    ) -> Animation? {
        guard allowsMotion(
            userEnabled: enabled,
            reduceMotion: reduceMotion
        ) else { return nil }
        return .smooth(duration: colorDuration, extraBounce: 0)
    }

    static func press(reduceMotion: Bool) -> Animation? {
        allowsMotion(userEnabled: true, reduceMotion: reduceMotion)
            ? .snappy(duration: pressDuration, extraBounce: 0)
            : nil
    }

    static func flowStretch(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? nil
            : .smooth(duration: flowStretchDuration, extraBounce: 0)
    }

    static func flowSquash(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? nil
            : .snappy(duration: flowSquashDuration, extraBounce: 0)
    }

    static func flowSettle(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? nil
            : .smooth(duration: flowSettleDuration, extraBounce: 0)
    }

    static func refreshDisappear(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? nil
            : .smooth(
                duration: IndicatorRefreshTiming.disappearDuration,
                extraBounce: 0
            )
    }

    static func refreshAppear(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? nil
            : .smooth(
                duration: IndicatorRefreshTiming.appearDuration,
                extraBounce: 0
            )
    }
}
