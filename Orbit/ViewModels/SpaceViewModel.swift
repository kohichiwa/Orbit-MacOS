import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class SpaceViewModel: ObservableObject {
    @Published private(set) var spaceCount: Int
    @Published private(set) var activeIndex: Int?
    @Published private(set) var indicatorKinds: [SpaceIndicatorKind]
    @Published private(set) var indicators: [SpaceIndicatorEntry]
    @Published private(set) var isSwitching = false
    @Published private(set) var canPostEvents: Bool
    @Published private(set) var message: String?

    private let reader: any SpacesReading
    private let controller: any SpaceControlling
    private let colorAssignments: any DesktopColorSlotAssigning
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Orbit", category: "Spaces")
    private var snapshot: SpaceSnapshot?
    private var pendingTargetIdentifier: Int64?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt = 0
    private var fullscreenColorIndices: [Int64: Int] = [:]

    init(
        reader: any SpacesReading = SystemSpacesReader(),
        controller: any SpaceControlling = SystemSpaceController(),
        colorAssignments: any DesktopColorSlotAssigning = TransientDesktopColorSlots(),
        previewSnapshot: SpaceSnapshot? = nil
    ) {
        self.reader = reader
        self.controller = controller
        self.colorAssignments = colorAssignments
        snapshot = previewSnapshot
        spaceCount = previewSnapshot?.count ?? 1
        activeIndex = previewSnapshot?.activeIndex
        indicatorKinds = previewSnapshot?.indicatorKinds
            ?? [.desktop(colorIndex: 0)]
        indicators = previewSnapshot?.indicators
            ?? [SpaceIndicatorEntry(id: 0, kind: .desktop(colorIndex: 0))]
        canPostEvents = controller.canPostEvents
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
        canPostEvents = controller.canPostEvents
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
        apply(newSnapshot, preservingPendingSelection: isSwitching)
    }

    func select(_ index: Int) async {
        guard !isSwitching else { return }
        guard
            let snapshot,
            snapshot.orderedIdentifiers.indices.contains(index)
        else {
            await refresh()
            return
        }

        let targetIdentifier = snapshot.orderedIdentifiers[index]
        guard targetIdentifier != snapshot.activeIdentifier else { return }

        refreshGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil

        canPostEvents = controller.canPostEvents
        guard canPostEvents else {
            message = OrbitL10n.text(
                "error.spaceSwitch.permissionRequired",
                fallback: "Orbit can't send the system shortcut. Allow control in the context menu."
            )
            return
        }

        isSwitching = true
        message = nil
        pendingTargetIdentifier = targetIdentifier
        activeIndex = index

        do {
            let freshSnapshot = await reader.read()
            var current = freshSnapshot?.activeIdentifier == nil
                ? snapshot
                : freshSnapshot ?? snapshot
            let maximumMoves = max(current.orderedIdentifiers.count * 2, 4)

            for _ in 0..<maximumMoves {
                try Task.checkCancellation()
                if current.activeIdentifier == targetIdentifier {
                    finishSwitch(with: current)
                    return
                }
                guard let direction = current.direction(toward: targetIdentifier) else {
                    throw SpaceSwitchError.targetUnavailable
                }

                let previousIdentifier = current.activeIdentifier
                try await controller.move(direction)
                guard let changed = await waitForChange(from: previousIdentifier) else {
                    throw SpaceSwitchError.systemDidNotSwitch
                }
                current = changed
                apply(current, preservingPendingSelection: true)
            }
            throw SpaceSwitchError.targetUnavailable
        } catch is CancellationError {
            await reconcileAfterFailure()
        } catch {
            logger.error("Space switch failed: \(error.localizedDescription)")
            await reconcileAfterFailure()
            message = error.localizedDescription
        }
    }

    @discardableResult
    func requestEventPostingAccess() -> Bool {
        let granted = controller.requestAccessibilityPermission()
        canPostEvents = controller.canPostEvents
        return granted
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func waitForChange(from previousIdentifier: Int64?) async -> SpaceSnapshot? {
        for attempt in 0..<24 {
            if Task.isCancelled { return nil }
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(80)) }
            guard let candidate = await reader.read() else { continue }
            guard candidate.activeIdentifier != nil else { continue }
            if candidate.activeIdentifier != previousIdentifier {
                return candidate
            }
        }
        return nil
    }

    private func finishSwitch(with newSnapshot: SpaceSnapshot) {
        let newSnapshot = assigningFullscreenColors(in: newSnapshot)
        pendingTargetIdentifier = nil
        publishStructure(from: newSnapshot)
        publishActiveIndex(newSnapshot.activeIndex)
        isSwitching = false
        publishMessage(nil)
    }

    private func reconcileAfterFailure() async {
        pendingTargetIdentifier = nil
        if let actual = await reader.read(), actual.activeIdentifier != nil {
            let actual = assigningFullscreenColors(in: actual)
            publishStructure(from: actual)
            publishActiveIndex(actual.activeIndex)
        } else {
            publishActiveIndex(snapshot?.activeIndex)
        }
        isSwitching = false
    }

    private func systemSpaceDidChange() {
        guard !isSwitching else { return }
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
                    self.apply(candidate, preservingPendingSelection: false)
                    return
                }
            }
        }
    }

    private func apply(_ newSnapshot: SpaceSnapshot, preservingPendingSelection: Bool) {
        // WindowServer can briefly omit Current Space while the menu bar changes
        // appearance. Keeping the last confirmed snapshot prevents a one-frame
        // disappearance of the active indicator.
        guard newSnapshot.activeIdentifier != nil else { return }
        let newSnapshot = assigningFullscreenColors(in: newSnapshot)

        publishStructure(from: newSnapshot)

        if preservingPendingSelection,
           let pendingTargetIdentifier,
           newSnapshot.activeIdentifier != pendingTargetIdentifier {
            return
        }

        publishActiveIndex(newSnapshot.activeIndex)
        if newSnapshot.activeIdentifier == pendingTargetIdentifier {
            self.pendingTargetIdentifier = nil
        }
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

private enum SpaceSwitchError: LocalizedError {
    case targetUnavailable
    case systemDidNotSwitch

    var errorDescription: String? {
        switch self {
        case .targetUnavailable:
            OrbitL10n.text(
                "error.spaceSwitch.targetUnavailable",
                fallback: "macOS changed the desktop order. Try again."
            )
        case .systemDidNotSwitch:
            OrbitL10n.text(
                "error.spaceSwitch.systemDidNotSwitch",
                fallback: "macOS didn't perform Control+Left/Right. Check the Mission Control shortcuts in Keyboard settings."
            )
        }
    }
}
