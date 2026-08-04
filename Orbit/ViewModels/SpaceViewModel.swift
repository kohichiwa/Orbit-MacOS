import AppKit
import Combine
import Foundation

@MainActor
final class SpaceViewModel: ObservableObject {
    @Published private(set) var spaceCount: Int
    @Published private(set) var activeIndex: Int?
    @Published private(set) var indicatorKinds: [SpaceIndicatorKind]
    @Published private(set) var indicators: [SpaceIndicatorEntry]
    @Published private(set) var message: String?

    private let reader: any SpacesReading
    private let colorAssignments: any DesktopColorSlotAssigning
    private var snapshot: SpaceSnapshot?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt = 0
    private var fullscreenColorIndices: [Int64: Int] = [:]

    init(
        reader: any SpacesReading = SystemSpacesReader(),
        colorAssignments: any DesktopColorSlotAssigning = TransientDesktopColorSlots(),
        previewSnapshot: SpaceSnapshot? = nil
    ) {
        self.reader = reader
        self.colorAssignments = colorAssignments
        snapshot = previewSnapshot
        spaceCount = previewSnapshot?.count ?? 1
        activeIndex = previewSnapshot?.activeIndex
        indicatorKinds = previewSnapshot?.indicatorKinds
            ?? [.desktop(colorIndex: 0)]
        indicators = previewSnapshot?.indicators
            ?? [SpaceIndicatorEntry(id: 0, kind: .desktop(colorIndex: 0))]
        if let previewSnapshot {
            for entry in previewSnapshot.indicators where entry.kind.isFullscreen {
                fullscreenColorIndices[entry.id] = entry.kind.colorIndex
            }
        }
    }

    nonisolated deinit {}

    func start() {
        reader.start { [weak self] in self?.systemSpaceDidChange() }
        scheduleRefresh()
    }

    func stop() {
        refreshGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        reader.stop()
    }

    func refresh() async {
        refreshTask?.cancel()
        let generation = nextRefreshGeneration()
        await performRefresh(generation: generation)
    }

    private func performRefresh(generation: UInt) async {
        let newSnapshot = await reader.read()
        guard isCurrentRefresh(generation) else { return }
        guard let newSnapshot else {
            publishMessage(
                OrbitL10n.text(
                "error.desktopList.unavailable",
                fallback: "Couldn't read the macOS desktop list."
                )
            )
            return
        }
        apply(newSnapshot)
    }

    private func systemSpaceDidChange() {
        let previousIdentifier = snapshot?.activeIdentifier
        let previousIndicators = snapshot?.indicators
        refreshTask?.cancel()
        let generation = nextRefreshGeneration()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for attempt in 0..<12 {
                guard self.isCurrentRefresh(generation) else { return }
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(70)) }
                guard self.isCurrentRefresh(generation) else { return }
                guard let candidate = await self.reader.read() else { continue }
                guard self.isCurrentRefresh(generation) else { return }
                guard candidate.activeIdentifier != nil else { continue }
                if candidate.activeIdentifier != previousIdentifier
                    || candidate.indicators != previousIndicators {
                    self.apply(candidate)
                    return
                }
            }
        }
    }

    private func apply(_ newSnapshot: SpaceSnapshot) {
        // WindowServer can briefly omit Current Space while the menu bar changes
        // appearance. Keeping the last confirmed snapshot prevents a one-frame
        // disappearance of the active indicator.
        guard newSnapshot.activeIdentifier != nil else { return }
        let newSnapshot = assigningFullscreenColors(in: newSnapshot)

        publishStructure(from: newSnapshot)
        publishActiveIndex(newSnapshot.activeIndex)
        publishMessage(nil)
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        let generation = nextRefreshGeneration()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(generation: generation)
        }
    }

    private func nextRefreshGeneration() -> UInt {
        refreshGeneration &+= 1
        return refreshGeneration
    }

    private func isCurrentRefresh(_ generation: UInt) -> Bool {
        !Task.isCancelled && generation == refreshGeneration
    }

    private func publishStructure(from newSnapshot: SpaceSnapshot) {
        snapshot = newSnapshot
        if spaceCount != newSnapshot.count {
            spaceCount = newSnapshot.count
        }
        if indicatorKinds != newSnapshot.indicatorKinds {
            indicatorKinds = newSnapshot.indicatorKinds
        }
        if indicators != newSnapshot.indicators {
            indicators = newSnapshot.indicators
        }
    }

    private func publishActiveIndex(_ newValue: Int?) {
        if activeIndex != newValue {
            activeIndex = newValue
        }
    }

    private func publishMessage(_ newValue: String?) {
        if message != newValue {
            message = newValue
        }
    }

    private func assigningFullscreenColors(
        in newSnapshot: SpaceSnapshot
    ) -> SpaceSnapshot {
        let previousActiveDesktopColor: Int?
        if let snapshot,
           let activeIndex = snapshot.activeIndex,
           snapshot.indicatorKinds.indices.contains(activeIndex),
           case .desktop(let colorIndex) = snapshot.indicatorKinds[activeIndex] {
            previousActiveDesktopColor = colorIndex
        } else {
            previousActiveDesktopColor = nil
        }

        let previousIdentifiers = Set(snapshot?.orderedIdentifiers ?? [])
        let desktopColorSlots = colorAssignments.colorSlots(
            for: newSnapshot.desktopIdentifiers
        )
        var retainedAssignments: [Int64: Int] = [:]
        var nearestDesktopColorIndex = 0
        let coloredKinds: [SpaceIndicatorKind] = zip(
            newSnapshot.orderedIdentifiers,
            newSnapshot.indicatorKinds
        ).map { identifier, kind in
            if case .desktop = kind {
                let colorIndex = desktopColorSlots[identifier]
                    ?? kind.colorIndex
                nearestDesktopColorIndex = colorIndex
                return .desktop(colorIndex: colorIndex)
            }

            let colorIndex = fullscreenColorIndices[identifier]
                ?? (!previousIdentifiers.contains(identifier)
                    ? previousActiveDesktopColor
                    : nil)
                ?? nearestDesktopColorIndex
            retainedAssignments[identifier] = colorIndex
            return .fullscreen(colorIndex: colorIndex)
        }
        fullscreenColorIndices = retainedAssignments

        return SpaceSnapshot(
            orderedIdentifiers: newSnapshot.orderedIdentifiers,
            desktopIdentifiers: newSnapshot.desktopIdentifiers,
            activeIdentifier: newSnapshot.activeIdentifier,
            indicatorKinds: coloredKinds
        )
    }
}

@MainActor
protocol DesktopColorSlotAssigning: AnyObject {
    func colorSlots(for desktopIdentifiers: [Int64]) -> [Int64: Int]
}

@MainActor
final class TransientDesktopColorSlots: DesktopColorSlotAssigning {
    private var slots: [Int64: Int] = [:]

    func colorSlots(for desktopIdentifiers: [Int64]) -> [Int64: Int] {
        slots = slots.filter { desktopIdentifiers.contains($0.key) }
        var usedSlots = Set(slots.values)
        for identifier in desktopIdentifiers where slots[identifier] == nil {
            let slot = (0...).first { !usedSlots.contains($0) }
                ?? usedSlots.count
            slots[identifier] = slot
            usedSlots.insert(slot)
        }

        let used = Array(Set(slots.values)).sorted()
        let remapping = Dictionary(
            uniqueKeysWithValues: used.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        slots = slots.mapValues { remapping[$0] ?? $0 }
        return slots
    }
}
