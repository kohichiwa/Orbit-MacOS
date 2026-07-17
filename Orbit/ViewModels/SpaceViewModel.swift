import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class SpaceViewModel: ObservableObject {
    @Published private(set) var spaceCount: Int
    @Published private(set) var activeIndex: Int?
    @Published private(set) var isSwitching = false
    @Published private(set) var canPostEvents: Bool
    @Published private(set) var message: String?

    private let reader: any SpacesReading
    private let controller: any SpaceControlling
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Orbit", category: "Spaces")
    private var snapshot: SpaceSnapshot?
    private var pendingTargetIdentifier: Int64?
    private var refreshTask: Task<Void, Never>?

    init(
        reader: any SpacesReading = SystemSpacesReader(),
        controller: any SpaceControlling = SystemSpaceController(),
        previewSnapshot: SpaceSnapshot? = nil
    ) {
        self.reader = reader
        self.controller = controller
        snapshot = previewSnapshot
        spaceCount = previewSnapshot?.count ?? 1
        activeIndex = previewSnapshot?.activeIndex
        canPostEvents = controller.canPostEvents
    }

    nonisolated deinit {}

    func start() {
        reader.start { [weak self] in self?.systemSpaceDidChange() }
        Task { await refresh() }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        reader.stop()
    }

    func refresh() async {
        canPostEvents = controller.canPostEvents
        guard let newSnapshot = await reader.read() else {
            message = "Не удалось прочитать список рабочих столов macOS."
            return
        }
        apply(newSnapshot, preservingPendingSelection: isSwitching)
    }

    func select(_ index: Int) async {
        guard !isSwitching else { return }
        guard
            let snapshot,
            snapshot.desktopIdentifiers.indices.contains(index)
        else {
            await refresh()
            return
        }

        let targetIdentifier = snapshot.desktopIdentifiers[index]
        guard targetIdentifier != snapshot.activeIdentifier else { return }

        canPostEvents = controller.canPostEvents
        guard canPostEvents else {
            message = "Orbit не может отправить системное сочетание. Разрешите управление в контекстном меню."
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
        pendingTargetIdentifier = nil
        snapshot = newSnapshot
        spaceCount = newSnapshot.count
        activeIndex = newSnapshot.activeIndex
        isSwitching = false
        message = nil
    }

    private func reconcileAfterFailure() async {
        pendingTargetIdentifier = nil
        if let actual = await reader.read(), actual.activeIdentifier != nil {
            snapshot = actual
            spaceCount = actual.count
            activeIndex = actual.activeIndex
        } else {
            activeIndex = snapshot?.activeIndex
        }
        isSwitching = false
    }

    private func systemSpaceDidChange() {
        guard !isSwitching else { return }
        let previousIdentifier = snapshot?.activeIdentifier
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for attempt in 0..<12 {
                if Task.isCancelled { return }
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(70)) }
                guard let candidate = await self.reader.read() else { continue }
                guard candidate.activeIdentifier != nil else { continue }
                if candidate.activeIdentifier != previousIdentifier {
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

        snapshot = newSnapshot
        spaceCount = newSnapshot.count

        if preservingPendingSelection,
           let pendingTargetIdentifier,
           newSnapshot.activeIdentifier != pendingTargetIdentifier {
            return
        }

        activeIndex = newSnapshot.activeIndex
        if newSnapshot.activeIdentifier == pendingTargetIdentifier {
            self.pendingTargetIdentifier = nil
        }
        message = nil
    }
}

private enum SpaceSwitchError: LocalizedError {
    case targetUnavailable
    case systemDidNotSwitch

    var errorDescription: String? {
        switch self {
        case .targetUnavailable:
            "macOS изменила порядок рабочих столов. Повторите нажатие."
        case .systemDidNotSwitch:
            "macOS не выполнила Control+←/→. Проверьте сочетания Mission Control в настройках клавиатуры."
        }
    }
}
