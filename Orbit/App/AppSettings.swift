import AppKit
import Combine
import Foundation
import ServiceManagement

enum IndicatorAnimationStyle: String, CaseIterable, Identifiable {
    case classic
    case seamless
    case continuous

    var id: Self { self }

    var title: String {
        switch self {
        case .seamless:
            OrbitL10n.text(
                "settings.animation.seamless",
                fallback: "Seamless"
            )
        case .classic:
            OrbitL10n.text(
                "settings.animation.classic",
                fallback: "Classic"
            )
        case .continuous:
            OrbitL10n.text(
                "settings.animation.continuous",
                fallback: "Continuous"
            )
        }
    }

    var blendsIndicatorAppearanceDuringTransition: Bool {
        switch self {
        case .classic:
            false
        case .seamless, .continuous:
            true
        }
    }
}

enum IndicatorShapeStyle: String, CaseIterable, Identifiable {
    case standard
    case circles
    case roundedRectangles

    var id: Self { self }

    var title: String {
        switch self {
        case .standard:
            OrbitL10n.text(
                "settings.shape.standard",
                fallback: "Standard"
            )
        case .circles:
            OrbitL10n.text(
                "settings.shape.circles",
                fallback: "Circles"
            )
        case .roundedRectangles:
            OrbitL10n.text(
                "settings.shape.roundedRectangles",
                fallback: "Rounded rectangles"
            )
        }
    }
}

enum VisualSettingsChange {
    case layout
    case colors
    case outline
    case animationEnabled(Bool)
    case animationStyle
    case shapeStyle
    case applicationsOnHover(Bool)
}

@MainActor
final class AppSettings: ObservableObject, DesktopColorSlotAssigning {
    private enum Key {
        static let animateIndicator = "animateIndicator"
        static let indicatorAnimationStyle = "indicatorAnimationStyle"
        // V2 distinguishes the three real silhouettes from the earlier
        // two-option prototype where `circles` meant the standard dot + pill.
        static let indicatorShapeStyle = "indicatorShapeStyleV2"
        static let indicatorSizeScale = "indicatorSizeScale"
        static let indicatorSpacingScale = "indicatorSpacingScale"
        static let showsIndicatorOutline = "showsIndicatorOutline"
        static let showsApplicationsOnHover = "showsApplicationsOnHover"
        static let indicatorColorComponents = "indicatorColorComponents"
        static let indicatorColorsComponents = "indicatorColorsComponents"
        static let desktopColorSlots = "desktopColorSlotsBySpaceIdentifier"
    }

    static let indicatorSizeSteps: [Double] = [
        0.9, 1, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7
    ]
    static let indicatorSpacingSteps: [Double] = [
        1,
        1 + 1.0 / 12,
        1 + 2.0 / 12,
        1 + 3.0 / 12,
        1 + 4.0 / 12,
        1 + 5.0 / 12,
        1.5,
        1 + 7.0 / 12,
        1 + 8.0 / 12
    ]

    let visualSettingsChanges = PassthroughSubject<VisualSettingsChange, Never>()

    @Published var animateIndicator: Bool {
        didSet {
            defaults.set(animateIndicator, forKey: Key.animateIndicator)
            visualSettingsChanges.send(.animationEnabled(animateIndicator))
        }
    }

    @Published var indicatorAnimationStyle: IndicatorAnimationStyle {
        didSet {
            defaults.set(
                indicatorAnimationStyle.rawValue,
                forKey: Key.indicatorAnimationStyle
            )
            visualSettingsChanges.send(.animationStyle)
        }
    }

    @Published var indicatorShapeStyle: IndicatorShapeStyle {
        didSet {
            defaults.set(
                indicatorShapeStyle.rawValue,
                forKey: Key.indicatorShapeStyle
            )
            visualSettingsChanges.send(.shapeStyle)
        }
    }

    @Published var indicatorSizeScale: Double {
        didSet {
            defaults.set(indicatorSizeScale, forKey: Key.indicatorSizeScale)
            visualSettingsChanges.send(.layout)
        }
    }

    @Published var indicatorSpacingScale: Double {
        didSet {
            defaults.set(indicatorSpacingScale, forKey: Key.indicatorSpacingScale)
            visualSettingsChanges.send(.layout)
        }
    }

    @Published var showsIndicatorOutline: Bool {
        didSet {
            defaults.set(
                showsIndicatorOutline,
                forKey: Key.showsIndicatorOutline
            )
            visualSettingsChanges.send(.outline)
        }
    }

    @Published var showsApplicationsOnHover: Bool {
        didSet {
            defaults.set(
                showsApplicationsOnHover,
                forKey: Key.showsApplicationsOnHover
            )
            visualSettingsChanges.send(
                .applicationsOnHover(showsApplicationsOnHover)
            )
        }
    }

    @Published private(set) var indicatorColors: [NSColor] {
        didSet {
            defaults.set(
                indicatorColors.map(Self.colorComponents),
                forKey: Key.indicatorColorsComponents
            )
            visualSettingsChanges.send(.colors)
        }
    }

    @Published private(set) var message: String?

    private let defaults: UserDefaults
    private var desktopColorSlots: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        desktopColorSlots = Self.storedDesktopColorSlots(in: defaults)
        animateIndicator = defaults.object(forKey: Key.animateIndicator) == nil
            ? true
            : defaults.bool(forKey: Key.animateIndicator)
        indicatorAnimationStyle = defaults
            .string(forKey: Key.indicatorAnimationStyle)
            .flatMap(IndicatorAnimationStyle.init(rawValue:))
            ?? .seamless
        indicatorShapeStyle = defaults
            .string(forKey: Key.indicatorShapeStyle)
            .flatMap(IndicatorShapeStyle.init(rawValue:))
            ?? .standard
        indicatorSizeScale = Self.normalizedIndicatorSize(
            defaults.object(forKey: Key.indicatorSizeScale) == nil
                ? 1
                : defaults.double(forKey: Key.indicatorSizeScale)
        )
        indicatorSpacingScale = Self.normalizedIndicatorSpacing(
            defaults.object(forKey: Key.indicatorSpacingScale) == nil
                ? 1
                : defaults.double(forKey: Key.indicatorSpacingScale)
        )
        showsIndicatorOutline = defaults.bool(
            forKey: Key.showsIndicatorOutline
        )
        showsApplicationsOnHover = defaults.object(
            forKey: Key.showsApplicationsOnHover
        ) == nil
            ? true
            : defaults.bool(forKey: Key.showsApplicationsOnHover)
        indicatorColors = Self.storedIndicatorColors(in: defaults)
        if indicatorColors.isEmpty,
           let legacyColor = Self.storedIndicatorColor(in: defaults) {
            indicatorColors = Array(repeating: legacyColor, count: 16)
        }

        defaults.set(indicatorSizeScale, forKey: Key.indicatorSizeScale)
        defaults.set(indicatorSpacingScale, forKey: Key.indicatorSpacingScale)
        defaults.set(
            indicatorAnimationStyle.rawValue,
            forKey: Key.indicatorAnimationStyle
        )
        defaults.set(
            indicatorShapeStyle.rawValue,
            forKey: Key.indicatorShapeStyle
        )
        defaults.set(
            showsApplicationsOnHover,
            forKey: Key.showsApplicationsOnHover
        )
        defaults.set(
            indicatorColors.map(Self.colorComponents),
            forKey: Key.indicatorColorsComponents
        )
    }

    nonisolated deinit {}

    var launchAtLoginState: NSControl.StateValue {
        switch SMAppService.mainApp.status {
        case .enabled:
            .on
        case .requiresApproval:
            .mixed
        default:
            .off
        }
    }

    func toggleLaunchAtLogin() {
        message = nil
        defer { objectWillChange.send() }
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notRegistered, .notFound:
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            @unknown default:
                try SMAppService.mainApp.register()
            }
        } catch {
            message = OrbitL10n.format(
                "error.loginItem.update",
                fallback: "Couldn't change launch at login: %@",
                error.localizedDescription
            )
        }
    }

    func setIndicatorSizeScale(_ value: Double) {
        message = nil
        let value = Self.normalizedIndicatorSize(value)
        guard indicatorSizeScale != value else { return }
        indicatorSizeScale = value
    }

    func setIndicatorSpacingScale(_ value: Double) {
        message = nil
        let value = Self.normalizedIndicatorSpacing(value)
        guard indicatorSpacingScale != value else { return }
        indicatorSpacingScale = value
    }

    func indicatorColors(for count: Int) -> [NSColor] {
        let count = max(count, 1)
        let defaultColor = Self.normalizedIndicatorColor(.controlAccentColor)
        return (0..<count).map { index in
            indicatorColors.indices.contains(index)
                ? indicatorColors[index]
                : defaultColor
        }
    }

    func setIndicatorColor(_ color: NSColor, at index: Int) {
        guard index >= 0 else { return }
        let defaultColor = Self.normalizedIndicatorColor(.controlAccentColor)
        let normalizedColor = Self.normalizedIndicatorColor(color)
        var updatedColors = indicatorColors
        if updatedColors.count <= index {
            updatedColors.append(
                contentsOf: repeatElement(
                    defaultColor,
                    count: index - updatedColors.count + 1
                )
            )
        }
        message = nil
        guard !updatedColors[index].isEqual(normalizedColor) else { return }
        updatedColors[index] = normalizedColor
        indicatorColors = updatedColors
    }

    func resetIndicatorColors() {
        defaults.removeObject(forKey: Key.indicatorColorComponents)
        defaults.removeObject(forKey: Key.indicatorColorsComponents)
        indicatorColors = []
        message = nil
    }

    func colorSlots(for desktopIdentifiers: [Int64]) -> [Int64: Int] {
        let previousSlots = desktopColorSlots
        let currentKeys = Set(desktopIdentifiers.map(String.init))
        desktopColorSlots = desktopColorSlots.filter {
            currentKeys.contains($0.key)
        }

        var usedSlots = Set(desktopColorSlots.values.filter { $0 >= 0 })
        for identifier in desktopIdentifiers {
            let key = String(identifier)
            guard desktopColorSlots[key] == nil else { continue }
            let slot = (0...).first { !usedSlots.contains($0) }
                ?? usedSlots.count
            desktopColorSlots[key] = slot
            usedSlots.insert(slot)
        }

        compactDesktopColorSlotsIfNeeded()
        if desktopColorSlots != previousSlots {
            defaults.set(desktopColorSlots, forKey: Key.desktopColorSlots)
        }
        return Dictionary(
            uniqueKeysWithValues: desktopIdentifiers.compactMap { identifier in
                desktopColorSlots[String(identifier)].map { (identifier, $0) }
            }
        )
    }

    static func normalizedIndicatorSize(_ value: Double) -> Double {
        nearestStep(to: value, in: indicatorSizeSteps)
    }

    static func normalizedIndicatorSpacing(_ value: Double) -> Double {
        nearestStep(to: value, in: indicatorSpacingSteps)
    }

    private static func nearestStep(
        to value: Double,
        in steps: [Double]
    ) -> Double {
        steps.min { abs($0 - value) < abs($1 - value) } ?? 1
    }

    private static func storedIndicatorColor(in defaults: UserDefaults) -> NSColor? {
        guard
            let values = defaults.array(forKey: Key.indicatorColorComponents),
            values.count == 3,
            let red = values[0] as? NSNumber,
            let green = values[1] as? NSNumber,
            let blue = values[2] as? NSNumber
        else { return nil }
        return NSColor(
            srgbRed: red.doubleValue,
            green: green.doubleValue,
            blue: blue.doubleValue,
            alpha: 1
        )
    }

    private static func storedIndicatorColors(
        in defaults: UserDefaults
    ) -> [NSColor] {
        guard let stored = defaults.array(forKey: Key.indicatorColorsComponents)
        else { return [] }
        return stored.compactMap { entry in
            guard
                let values = entry as? [NSNumber],
                values.count == 3
            else { return nil }
            return NSColor(
                srgbRed: values[0].doubleValue,
                green: values[1].doubleValue,
                blue: values[2].doubleValue,
                alpha: 1
            )
        }
    }

    private static func storedDesktopColorSlots(
        in defaults: UserDefaults
    ) -> [String: Int] {
        guard let stored = defaults.dictionary(forKey: Key.desktopColorSlots)
        else { return [:] }
        return stored.reduce(into: [:]) { result, entry in
            if let value = entry.value as? NSNumber, value.intValue >= 0 {
                result[entry.key] = value.intValue
            }
        }
    }

    private func compactDesktopColorSlotsIfNeeded() {
        let usedSlots = Array(Set(desktopColorSlots.values)).sorted()
        let compactRange = Array(0..<usedSlots.count)
        guard
            usedSlots != compactRange
                || indicatorColors.count != usedSlots.count
        else { return }

        let remapping = Dictionary(
            uniqueKeysWithValues: usedSlots.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        let previousColors = indicatorColors
        for (identifier, oldSlot) in desktopColorSlots {
            desktopColorSlots[identifier] = remapping[oldSlot]
        }

        var compactedColors = indicatorColors
        let defaultColor = Self.normalizedIndicatorColor(.controlAccentColor)
        if compactedColors.count < usedSlots.count {
            compactedColors.append(
                contentsOf: repeatElement(
                    defaultColor,
                    count: usedSlots.count - compactedColors.count
                )
            )
        }
        for (oldSlot, newSlot) in remapping
        where previousColors.indices.contains(oldSlot) {
            compactedColors[newSlot] = previousColors[oldSlot]
        }
        indicatorColors = Array(compactedColors.prefix(usedSlots.count))
    }

    private static func normalizedIndicatorColor(_ color: NSColor) -> NSColor {
        guard let converted = color.usingColorSpace(.sRGB) else {
            return .controlAccentColor
        }
        return NSColor(
            srgbRed: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: 1
        )
    }

    private static func colorComponents(_ color: NSColor) -> [Double] {
        let color = normalizedIndicatorColor(color)
        return [color.redComponent, color.greenComponent, color.blueComponent]
    }
}
