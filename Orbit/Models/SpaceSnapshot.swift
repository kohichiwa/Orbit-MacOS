import Foundation

struct SpaceSnapshot: Equatable, Sendable {
    /// Every Space in Mission Control order. Full-screen Spaces stay here because
    /// Control+←/→ traverses them too.
    let orderedIdentifiers: [Int64]

    /// Only regular desktop Spaces. These are the dots Orbit displays.
    let desktopIdentifiers: [Int64]
    let activeIdentifier: Int64?

    var count: Int { desktopIdentifiers.count }
    var activeIndex: Int? {
        guard let activeIdentifier else { return nil }
        return desktopIdentifiers.firstIndex(of: activeIdentifier)
    }

    nonisolated init(
        orderedIdentifiers: [Int64],
        desktopIdentifiers: [Int64],
        activeIdentifier: Int64?
    ) {
        self.orderedIdentifiers = orderedIdentifiers
        self.desktopIdentifiers = desktopIdentifiers
        self.activeIdentifier = activeIdentifier
    }

    /// Convenient initializer for previews and tests where every Space is a desktop.
    nonisolated init(identifiers: [Int64], activeIndex: Int?) {
        orderedIdentifiers = identifiers
        desktopIdentifiers = identifiers
        if let activeIndex, identifiers.indices.contains(activeIndex) {
            activeIdentifier = identifiers[activeIndex]
        } else {
            activeIdentifier = nil
        }
    }

    func direction(toward targetIdentifier: Int64) -> SpaceDirection? {
        guard
            let activeIdentifier,
            let current = orderedIdentifiers.firstIndex(of: activeIdentifier),
            let target = orderedIdentifiers.firstIndex(of: targetIdentifier),
            current != target
        else { return nil }
        return target < current ? .previous : .next
    }
}
