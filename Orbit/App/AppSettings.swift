import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject, DesktopColorSlotAssigning {
    private enum Key {
        static let animateIndicator = "animateIndicator"
        static let indicatorSizeScale = "indicatorSizeScale"
        static let indicatorSpacingScale = "indicatorSpacingScale"
        static let indicatorColorComponents = "indicatorColorComponents"
        static let indicatorColorsComponents = "indicatorColorsComponents"
        static let desktopColorSlots = "desktopColorSlotsBySpaceIdentifier"
    }

    static let indicatorSizeSteps: [Double] = [0.9, 1, 1.1, 1.2, 1.3, 1.4, 1.5]
    static let indicatorSpacingSteps: [Double] = [
        1,
        1 + 1.0 / 12,
        1 + 2.0 / 12,
        1 + 3.0 / 12,
        1 + 4.0 / 12,
        1 + 5.0 / 12,
        1.5
    ]

    @Published var animateIndicator: Bool {
        didSet {
            defaults.set(animateIndicator, forKey: Key.animateIndicator)
        }
    }

    @Published var indicatorSizeScale: Double {
        didSet {
            defaults.set(indicatorSizeScale, forKey: Key.indicatorSizeScale)
        }
    }

    @Published var indicatorSpacingScale: Double {
        didSet {
            defaults.set(indicatorSpacingScale, forKey: Key.indicatorSpacingScale)
        }
    }

    @Published private(set) var indicatorColors: [NSColor] {
        didSet {
            defaults.set(
                indicatorColors.map(Self.colorComponents),
                forKey: Key.indicatorColorsComponents
            )
        }
    }

    @Published private(set) var message: String?

    private let defaults: UserDefaults
    private var desktopColorSlots: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        desktopColorSlots = Self.storedDesktopColorSlots(in: defaults)
        if defaults.object(forKey: Key.animateIndicator) == nil {
            animateIndicator = true
        } else {
            animateIndicator = defaults.bool(forKey: Key.animateIndicator)
        }
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
        indicatorColors = Self.storedIndicatorColors(in: defaults)
        if indicatorColors.isEmpty,
           let legacyColor = Self.storedIndicatorColor(in: defaults) {
            // Migrate the former global color to every macOS desktop slot.
            indicatorColors = Array(repeating: legacyColor, count: 16)
        }
        defaults.set(indicatorSizeScale, forKey: Key.indicatorSizeScale)
        defaults.set(indicatorSpacingScale, forKey: Key.indicatorSpacingScale)
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
            message = L10n.format("error.launchAtLogin", error.localizedDescription)
        }
    }

    func toggleAnimation() {
        animateIndicator.toggle()
        message = nil
    }

    func setIndicatorSizeScale(_ value: Double) {
        indicatorSizeScale = Self.normalizedIndicatorSize(value)
        message = nil
    }

    func setIndicatorSpacingScale(_ value: Double) {
        indicatorSpacingScale = Self.normalizedIndicatorSpacing(value)
        message = nil
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
        if indicatorColors.count <= index {
            indicatorColors.append(
                contentsOf: repeatElement(
                    defaultColor,
                    count: index - indicatorColors.count + 1
                )
            )
        }
        indicatorColors[index] = Self.normalizedIndicatorColor(color)
        message = nil
    }

    func resetIndicatorColors() {
        defaults.removeObject(forKey: Key.indicatorColorComponents)
        defaults.removeObject(forKey: Key.indicatorColorsComponents)
        indicatorColors = []
        message = nil
    }

    func colorSlots(for desktopIdentifiers: [Int64]) -> [Int64: Int] {
        let currentKeys = Set(desktopIdentifiers.map { String($0) })
        desktopColorSlots = desktopColorSlots.filter { currentKeys.contains($0.key) }

        var usedSlots = Set(desktopColorSlots.values.filter { $0 >= 0 })
        for identifier in desktopIdentifiers {
            let key = String(identifier)
            guard desktopColorSlots[key] == nil else { continue }
            let slot = (0...).first { !usedSlots.contains($0) } ?? usedSlots.count
            desktopColorSlots[key] = slot
            usedSlots.insert(slot)
        }

        compactDesktopColorSlotsIfNeeded()
        defaults.set(desktopColorSlots, forKey: Key.desktopColorSlots)
        return Dictionary(uniqueKeysWithValues: desktopIdentifiers.compactMap { identifier in
            desktopColorSlots[String(identifier)].map { (identifier, $0) }
        })
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

    private static func storedIndicatorColors(in defaults: UserDefaults) -> [NSColor] {
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
        guard let stored = defaults.dictionary(forKey: Key.desktopColorSlots) else {
            return [:]
        }
        return stored.reduce(into: [:]) { result, entry in
            if let value = entry.value as? NSNumber, value.intValue >= 0 {
                result[entry.key] = value.intValue
            }
        }
    }

    private func compactDesktopColorSlotsIfNeeded() {
        let usedSlots = Array(Set(desktopColorSlots.values)).sorted()
        guard usedSlots != Array(0..<usedSlots.count) else { return }

        let remapping = Dictionary(
            uniqueKeysWithValues: usedSlots.enumerated().map { ($0.element, $0.offset) }
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
        for (oldSlot, newSlot) in remapping where previousColors.indices.contains(oldSlot) {
            compactedColors[newSlot] = previousColors[oldSlot]
        }
        indicatorColors = compactedColors
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
        let converted = normalizedIndicatorColor(color)
        return [
            converted.redComponent,
            converted.greenComponent,
            converted.blueComponent
        ]
    }
}
