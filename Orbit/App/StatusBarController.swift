import AppKit
import Combine
import QuartzCore

@MainActor
final class StatusBarController: NSObject {
    private let viewModel: SpaceViewModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables = Set<AnyCancellable>()
    private var renderedSpaceCount = 0
    private var renderedActiveIndex: Int?
    private var renderedPillFrame: StatusPillFrame?
    private var artworkRenderer: StatusIndicatorImageRenderer?
    private var displayLink: CADisplayLink?
    private var pillMotion: StatusPillMotion?

    init(viewModel: SpaceViewModel) {
        self.viewModel = viewModel
        super.init()
        configureStatusItem()
        observeChanges()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = nil
        button.toolTip = "Orbit — рабочие столы"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: .leftMouseUp)
        button.setAccessibilityLabel("Рабочие столы")

        let rightClick = NSClickGestureRecognizer(
            target: self,
            action: #selector(statusItemRightClicked(_:))
        )
        rightClick.buttonMask = 0x2
        button.addGestureRecognizer(rightClick)

        updateArtwork(for: viewModel.spaceCount)
        configureDisplayLink(for: button)
        updateActivePill(to: viewModel.activeIndex, animated: false)
        updateToolTip(viewModel.message)
    }

    private func observeChanges() {
        viewModel.$spaceCount
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                self?.updateArtwork(for: count)
            }
            .store(in: &cancellables)

        viewModel.$activeIndex
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] index in
                self?.updateActivePill(to: index, animated: true)
                self?.updateAccessibilityValue(index)
            }
            .store(in: &cancellables)

        viewModel.$message
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.updateToolTip(message)
            }
            .store(in: &cancellables)
    }

    private func configureDisplayLink(for button: NSStatusBarButton) {
        let displayLink = button.displayLink(
            target: self,
            selector: #selector(advancePillMotion(_:))
        )
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: 120,
            preferred: 60
        )
        displayLink.isPaused = true
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func updateArtwork(for count: Int) {
        let count = max(count, 1)
        guard count != renderedSpaceCount else { return }
        renderedSpaceCount = count

        statusItem.length = StatusItemArtwork.preferredWidth(for: count)
        guard let button = statusItem.button else { return }

        let renderer = StatusIndicatorImageRenderer(count: count)
        artworkRenderer = renderer

        // This exact NSImage instance remains installed until the number of
        // Spaces changes. Animation only redraws its bitmap pixels; it
        // never replaces the button image or modifies the view hierarchy.
        button.image = renderer.image
        button.contentTintColor = nil

        if let index = viewModel.activeIndex, (0..<count).contains(index) {
            renderedActiveIndex = index
            renderPill(.resting(at: StatusItemArtwork.centerX(for: index)))
        } else {
            renderedActiveIndex = nil
            renderedPillFrame = nil
            renderer.update(pill: nil)
            button.needsDisplay = true
        }
    }

    private func updateActivePill(to index: Int?, animated: Bool) {
        guard
            let index,
            (0..<renderedSpaceCount).contains(index)
        else {
            stopPillMotion()
            renderedActiveIndex = nil
            renderedPillFrame = nil
            artworkRenderer?.update(pill: nil)
            statusItem.button?.needsDisplay = true
            return
        }

        let previousIndex = renderedActiveIndex
        let targetX = StatusItemArtwork.centerX(for: index)
        renderedActiveIndex = index

        guard
            animated,
            let previousIndex,
            previousIndex != index,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else {
            stopPillMotion()
            renderPill(.resting(at: targetX))
            return
        }

        let sourceX = pillMotion == nil
            ? StatusItemArtwork.centerX(for: previousIndex)
            : renderedPillFrame?.x ?? StatusItemArtwork.centerX(for: previousIndex)
        let motion = StatusPillMotion(
            fromX: sourceX,
            toX: targetX,
            initialWidth: renderedPillFrame?.width ?? 12,
            initialHeight: renderedPillFrame?.height ?? 7,
            startTime: CACurrentMediaTime()
        )
        pillMotion = motion
        renderPill(motion.frame(at: motion.startTime))
        displayLink?.isPaused = false
    }

    @objc private func advancePillMotion(_ displayLink: CADisplayLink) {
        guard let pillMotion else {
            displayLink.isPaused = true
            return
        }

        let frame = pillMotion.frame(at: displayLink.targetTimestamp)
        renderPill(frame)
        if frame.isComplete {
            self.pillMotion = nil
            displayLink.isPaused = true
        }
    }

    private func renderPill(_ frame: StatusPillFrame) {
        renderedPillFrame = frame
        artworkRenderer?.update(pill: frame)
        statusItem.button?.needsDisplay = true
    }

    private func stopPillMotion() {
        pillMotion = nil
        displayLink?.isPaused = true
    }

    private func updateAccessibilityValue(_ index: Int?) {
        guard let index else {
            statusItem.button?.setAccessibilityValue(nil)
            return
        }
        statusItem.button?.setAccessibilityValue(
            "Рабочий стол \(index + 1) из \(renderedSpaceCount)"
        )
    }

    private func updateToolTip(_ message: String?) {
        statusItem.button?.toolTip = message ?? "Orbit — рабочие столы"
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let point = sender.convert(event.locationInWindow, from: nil)
        let contentWidth = CGFloat(renderedSpaceCount) * StatusItemArtwork.itemWidth
        let leadingEdge = max((sender.bounds.width - contentWidth) / 2, 0)
        let relativeX = point.x - leadingEdge
        guard relativeX >= 0, relativeX < contentWidth else { return }

        let index = Int(relativeX / StatusItemArtwork.itemWidth)
        Task { await viewModel.select(index) }
    }

    @objc private func statusItemRightClicked(_ recognizer: NSClickGestureRecognizer) {
        guard
            let button = recognizer.view as? NSStatusBarButton,
            let event = NSApp.currentEvent
        else { return }
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: button)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        if let message = viewModel.message {
            let status = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            status.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: message)
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(.separator())
        }

        menu.addItem(item("Обновить", action: #selector(refresh), symbol: "arrow.clockwise"))
        if !viewModel.canPostEvents {
            menu.addItem(item("Разрешить управление…", action: #selector(requestAccess), symbol: "hand.raised"))
        }
        menu.addItem(.separator())
        menu.addItem(item("Завершить Orbit", action: #selector(quit), symbol: "power", key: "q"))
        return menu
    }

    private func item(_ title: String, action: Selector, symbol: String, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    @objc private func refresh() {
        Task { await viewModel.refresh() }
    }

    @objc private func requestAccess() {
        _ = viewModel.requestEventPostingAccess()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
