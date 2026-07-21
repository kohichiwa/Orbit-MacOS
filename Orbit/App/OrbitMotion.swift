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
    nonisolated static let hoverEnterDuration: TimeInterval = 0.22
    nonisolated static let hoverExitDuration: TimeInterval = 0.30
    nonisolated static let paletteDuration: TimeInterval = 0.28
    nonisolated static let colorDuration: TimeInterval = 0.20
    nonisolated static let pressDuration: TimeInterval = 0.10

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
        guard allowsMotion(
            userEnabled: enabled,
            reduceMotion: reduceMotion
        ) else { return nil }
        return .snappy(duration: paletteDuration, extraBounce: 0)
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
