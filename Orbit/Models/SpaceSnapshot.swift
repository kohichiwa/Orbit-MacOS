import Foundation

enum SpaceIndicatorKind: Equatable, Sendable {
    case desktop(colorIndex: Int)
    case fullscreen(colorIndex: Int)

    nonisolated var colorIndex: Int {
        switch self {
        case .desktop(let colorIndex), .fullscreen(let colorIndex):
            colorIndex
        }
    }

    nonisolated var isFullscreen: Bool {
        if case .fullscreen = self { return true }
        return false
    }
}

struct SpaceIndicatorEntry: Equatable, Sendable, Identifiable {
    let id: Int64
    let kind: SpaceIndicatorKind
}

struct SpaceSnapshot: Equatable, Sendable {
    /// Every Space in Mission Control order. Full-screen Spaces stay here because
    /// Control+←/→ traverses them too.
    let orderedIdentifiers: [Int64]

    /// Only regular desktop Spaces. Kept separately for desktop-specific state.
    let desktopIdentifiers: [Int64]
    /// One visual kind for every entry in `orderedIdentifiers`.
    let indicatorKinds: [SpaceIndicatorKind]
    let activeIdentifier: Int64?

    var count: Int { orderedIdentifiers.count }
    var activeIndex: Int? {
        guard let activeIdentifier else { return nil }
        return orderedIdentifiers.firstIndex(of: activeIdentifier)
    }
    var indicators: [SpaceIndicatorEntry] {
        zip(orderedIdentifiers, indicatorKinds).map {
            SpaceIndicatorEntry(id: $0.0, kind: $0.1)
        }
    }

    nonisolated init(
        orderedIdentifiers: [Int64],
        desktopIdentifiers: [Int64],
        activeIdentifier: Int64?,
        indicatorKinds: [SpaceIndicatorKind]? = nil
    ) {
        self.orderedIdentifiers = orderedIdentifiers
        self.desktopIdentifiers = desktopIdentifiers
        if let indicatorKinds,
           indicatorKinds.count == orderedIdentifiers.count {
            self.indicatorKinds = indicatorKinds
        } else {
            let desktopSet = Set(desktopIdentifiers)
            var desktopColorIndex = 0
            self.indicatorKinds = orderedIdentifiers.map { identifier in
                guard desktopSet.contains(identifier) else {
                    return .fullscreen(colorIndex: max(desktopColorIndex - 1, 0))
                }
                defer { desktopColorIndex += 1 }
                return .desktop(colorIndex: desktopColorIndex)
            }
        }
        self.activeIdentifier = activeIdentifier
    }

    /// Convenient initializer for previews and tests where every Space is a desktop.
    nonisolated init(identifiers: [Int64], activeIndex: Int?) {
        orderedIdentifiers = identifiers
        desktopIdentifiers = identifiers
        indicatorKinds = identifiers.indices.map {
            .desktop(colorIndex: $0)
        }
        if let activeIndex, identifiers.indices.contains(activeIndex) {
            activeIdentifier = identifiers[activeIndex]
        } else {
            activeIdentifier = nil
        }
    }
}
