import AppKit
import Combine
import QuartzCore

@MainActor
private final class StatusHoverTrackingView: NSView {
    var eventHandler: (NSEvent?) -> Void
    private var hoverTrackingArea: NSTrackingArea?

    init(eventHandler: @escaping (NSEvent?) -> Void) {
        self.eventHandler = eventHandler
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    /// The status-bar button remains the click target; this view only owns
    /// its independent tracking area.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let hoverTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .activeAlways,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .mouseMoved
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(hoverTrackingArea)
        self.hoverTrackingArea = hoverTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        eventHandler(event)
    }

    override func mouseMoved(with event: NSEvent) {
        eventHandler(event)
    }

    override func mouseExited(with event: NSEvent) {
        eventHandler(nil)
    }
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let viewModel: SpaceViewModel
    private let settings: AppSettings
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables = Set<AnyCancellable>()
    private var renderedSpaceCount = 0
    private var renderedIndicatorKinds: [SpaceIndicatorKind] = []
    private var renderedActiveIndex: Int?
    private var renderedPillFrame: StatusPillFrame?
    private var artworkRenderer: StatusIndicatorImageRenderer?
    private var displayLink: CADisplayLink?
    private var pillMotion: StatusPillMotion?
    private var transitionSourceIndex: Int?
    private var hoverTrackingView: StatusHoverTrackingView?
    private var hoveredIndex: Int?
    private var hoverScales: [Int: CGSize] = [:]
    private var hoverMotions: [Int: StatusHoverMotion] = [:]
    private var artworkPresentation: StatusArtworkPresentation = .identity
    private var artworkRefreshMotion: StatusArtworkRefreshMotion?
    private var artworkRefreshDidApplySettings = false
    private var presentedSizeScale: CGFloat
    private var presentedSpacingScale: CGFloat
    private var presentedAnimationsEnabled: Bool
    private var presentedAnimationStyle: IndicatorAnimationStyle
    private var presentedMenu: NSMenu?
    private lazy var settingsWindowController = SettingsWindowController(
        settings: settings,
        viewModel: viewModel
    )

    init(viewModel: SpaceViewModel, settings: AppSettings) {
        self.viewModel = viewModel
        self.settings = settings
        presentedSizeScale = CGFloat(settings.indicatorSizeScale)
        presentedSpacingScale = CGFloat(settings.indicatorSpacingScale)
        presentedAnimationsEnabled = settings.animateIndicator
        presentedAnimationStyle = settings.indicatorAnimationStyle
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
        button.sendAction(on: [.leftMouseUp, .rightMouseDown])
        button.setAccessibilityLabel("Рабочие столы")

        updateArtwork(
            for: viewModel.spaceCount,
            indicatorKinds: viewModel.indicatorKinds
        )
        configureDisplayLink(for: button)
        configureHoverTracking(for: button)
        updateActivePill(to: viewModel.activeIndex, animated: false)
        updateToolTip(viewModel.message)
    }

    private func observeChanges() {
        Publishers.CombineLatest(
            viewModel.$spaceCount,
            viewModel.$indicatorKinds
        )
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] count, indicatorKinds in
                self?.updateArtwork(
                    for: count,
                    indicatorKinds: indicatorKinds
                )
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

        settings.visualSettingsChanges
            .sink { [weak self] change in
                guard let self else { return }
                switch change {
                case .colors:
                    refreshArtworkForSettings()
                case .layout:
                    applyPendingVisualSettings()
                case .animationEnabled(let enabled):
                    if enabled {
                        beginArtworkRefresh()
                    } else {
                        applyPendingVisualSettings()
                    }
                case .animationStyle:
                    beginArtworkRefresh()
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.accessibilityDisplayOptionsDidChange()
            }
            .store(in: &cancellables)
    }

    private func configureDisplayLink(for button: NSStatusBarButton) {
        let displayLink = button.displayLink(
            target: self,
            selector: #selector(advanceAnimations(_:))
        )
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: 120,
            preferred: 120
        )
        displayLink.isPaused = true
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
        updateDisplayLinkState()
    }

    private func configureHoverTracking(for button: NSStatusBarButton) {
        if let hoverTrackingView,
            hoverTrackingView.superview === button {
            hoverTrackingView.frame = button.bounds
            hoverTrackingView.updateTrackingAreas()
            synchronizeHoverLocation(for: button)
            return
        }

        hoverTrackingView?.removeFromSuperview()
        let trackingView = StatusHoverTrackingView {
            [weak self, weak button] event in
            guard let self, let button else { return }
            if let event {
                self.updateHover(with: event, in: button)
            } else {
                self.setHoveredIndex(nil)
            }
        }
        trackingView.frame = button.bounds
        trackingView.autoresizingMask = [.width, .height]
        button.addSubview(trackingView)
        hoverTrackingView = trackingView
        trackingView.updateTrackingAreas()
        synchronizeHoverLocation(for: button)
    }

    private func updateArtwork(
        for count: Int,
        indicatorKinds: [SpaceIndicatorKind],
        force: Bool = false
    ) {
        let count = max(count, 1)
        guard indicatorKinds.count == count else { return }
        guard
            force
                || count != renderedSpaceCount
                || indicatorKinds != renderedIndicatorKinds
        else { return }
        renderedSpaceCount = count
        renderedIndicatorKinds = indicatorKinds
        if let hoveredIndex, !(0..<count).contains(hoveredIndex) {
            self.hoveredIndex = nil
        }
        hoverScales = hoverScales.filter { (0..<count).contains($0.key) }
        hoverMotions = hoverMotions.filter { (0..<count).contains($0.key) }

        statusItem.length = StatusItemArtwork.preferredWidth(
            for: count,
            sizeScale: indicatorSizeScale,
            spacingScale: indicatorSpacingScale
        )
        guard let button = statusItem.button else { return }

        let renderer = StatusIndicatorImageRenderer(
            count: count,
            indicatorKinds: indicatorKinds,
            indicatorColors: settings.indicatorColors(
                for: renderedDesktopColorSlotCount
            ),
            sizeScale: indicatorSizeScale,
            spacingScale: indicatorSpacingScale,
            horizontalOverflowPadding: StatusItemArtwork.horizontalPadding(
                sizeScale: indicatorSizeScale
            )
        )
        artworkRenderer = renderer

        // This exact NSImage instance remains installed until the number of
        // Spaces changes. Animation only redraws its bitmap pixels; it
        // never replaces the button image or modifies the view hierarchy.
        button.image = renderer.image
        button.contentTintColor = nil

        if let index = viewModel.activeIndex, (0..<count).contains(index) {
            transitionSourceIndex = nil
            renderedActiveIndex = index
            renderPill(
                .resting(
                    at: indicatorCenterX(for: index),
                    sizeScale: indicatorSizeScale
                )
            )
        } else {
            transitionSourceIndex = nil
            renderedActiveIndex = nil
            renderedPillFrame = nil
            renderer.update(
                pill: nil,
                activeIndex: nil,
                hoverScales: hoverScales
            )
            button.needsDisplay = true
        }

        if hoverTrackingView != nil {
            configureHoverTracking(for: button)
        }
    }

    private func updateActivePill(to index: Int?, animated: Bool) {
        guard
            let index,
            (0..<renderedSpaceCount).contains(index)
        else {
            let previousIndex = renderedActiveIndex
            stopPillMotion()
            renderedActiveIndex = nil
            renderedPillFrame = nil
            if previousIndex != nil {
                retargetHoveredIndicator()
            }
            renderArtwork()
            return
        }

        let previousIndex = renderedActiveIndex
        let targetX = indicatorCenterX(for: index)
        renderedActiveIndex = index
        if previousIndex != index {
            retargetHoveredIndicator()
        }

        guard
            animated,
            let previousIndex,
            previousIndex != index,
            OrbitMotion.allowsMotion(
                userEnabled: presentedAnimationsEnabled,
                reduceMotion: NSWorkspace.shared
                    .accessibilityDisplayShouldReduceMotion
            )
        else {
            stopPillMotion()
            renderPill(
                .resting(at: targetX, sizeScale: indicatorSizeScale)
            )
            return
        }

        let sourceX = pillMotion == nil
            ? indicatorCenterX(for: previousIndex)
            : renderedPillFrame?.x ?? indicatorCenterX(for: previousIndex)
        let motion = StatusPillMotion(
            fromX: sourceX,
            toX: targetX,
            initialWidth: renderedPillFrame?.width ?? 12 * indicatorSizeScale,
            initialHeight: renderedPillFrame?.height ?? 7 * indicatorSizeScale,
            startTime: CACurrentMediaTime(),
            sizeScale: indicatorSizeScale,
            itemWidth: renderedItemWidth,
            style: presentedAnimationStyle
        )
        transitionSourceIndex = presentedAnimationStyle == .seamless
            ? previousIndex
            : nil
        pillMotion = motion
        renderPill(motion.frame(at: motion.startTime))
        displayLink?.isPaused = false
    }

    @objc private func advanceAnimations(_ displayLink: CADisplayLink) {
        let timestamp = displayLink.targetTimestamp
        var needsRender = false

        if let artworkRefreshMotion {
            let frame = artworkRefreshMotion.frame(at: timestamp)
            artworkPresentation = frame.presentation
            if frame.shouldApplySettings,
               !artworkRefreshDidApplySettings {
                artworkRefreshDidApplySettings = true
                applyPendingVisualSettings()
            }
            needsRender = true
            if frame.isComplete {
                self.artworkRefreshMotion = nil
                artworkPresentation = .identity
            }
        }

        if let pillMotion {
            let frame = pillMotion.frame(at: timestamp)
            renderedPillFrame = frame
            needsRender = true
            if frame.isComplete {
                self.pillMotion = nil
                transitionSourceIndex = nil
            }
        }

        for index in Array(hoverMotions.keys) {
            guard let motion = hoverMotions[index] else { continue }
            let frame = motion.frame(at: timestamp)
            hoverScales[index] = frame.scale
            needsRender = true
            if frame.isComplete {
                hoverMotions[index] = nil
                if motion.targetScale == CGSize(width: 1, height: 1) {
                    hoverScales[index] = nil
                }
            }
        }

        if needsRender {
            renderArtwork()
        }
        updateDisplayLinkState()
    }

    private func renderPill(_ frame: StatusPillFrame) {
        renderedPillFrame = frame
        renderArtwork()
    }

    private func renderArtwork() {
        artworkRenderer?.update(
            pill: renderedPillFrame,
            activeIndex: renderedActiveIndex,
            transitionSourceIndex: transitionSourceIndex,
            hoverScales: hoverScales,
            presentation: artworkPresentation
        )
        statusItem.button?.needsDisplay = true
    }

    private func stopPillMotion() {
        pillMotion = nil
        transitionSourceIndex = nil
        updateDisplayLinkState()
    }

    private func updateDisplayLinkState() {
        displayLink?.isPaused = pillMotion == nil
            && hoverMotions.isEmpty
            && artworkRefreshMotion == nil
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
        guard
            let eventType = NSApp.currentEvent?.type,
            eventType == .leftMouseUp || eventType == .rightMouseDown
        else { return }
        showContextMenu(from: sender)
    }

    private func indicatorIndex(
        at point: NSPoint,
        in button: NSStatusBarButton
    ) -> Int? {
        let contentWidth = CGFloat(renderedSpaceCount) * renderedItemWidth
        let leadingEdge = max((button.bounds.width - contentWidth) / 2, 0)
        let relativeX = point.x - leadingEdge
        guard relativeX >= 0, relativeX < contentWidth else { return nil }
        return Int(relativeX / renderedItemWidth)
    }

    private func updateHover(
        with event: NSEvent,
        in button: NSStatusBarButton
    ) {
        let point = button.convert(event.locationInWindow, from: nil)
        setHoveredIndex(indicatorIndex(at: point, in: button))
    }

    private func synchronizeHoverLocation(for button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let point = button.convert(
            window.mouseLocationOutsideOfEventStream,
            from: nil
        )
        setHoveredIndex(
            button.bounds.contains(point)
                ? indicatorIndex(at: point, in: button)
                : nil
        )
    }

    private func setHoveredIndex(_ index: Int?) {
        let normalizedIndex = index.flatMap {
            (0..<renderedSpaceCount).contains($0) ? $0 : nil
        }
        guard normalizedIndex != hoveredIndex else { return }
        let previousIndex = hoveredIndex
        hoveredIndex = normalizedIndex

        if let previousIndex {
            startHoverMotion(at: previousIndex, isHovered: false)
        }
        if let normalizedIndex {
            startHoverMotion(at: normalizedIndex, isHovered: true)
        }
    }

    private func retargetHoveredIndicator() {
        guard let hoveredIndex else { return }
        startHoverMotion(at: hoveredIndex, isHovered: true)
    }

    private func startHoverMotion(at index: Int, isHovered: Bool) {
        let motion = StatusHoverMotion(
            index: index,
            fromScale: hoverScales[index] ?? CGSize(width: 1, height: 1),
            isHovered: isHovered,
            isActive: index == renderedActiveIndex,
            startTime: CACurrentMediaTime()
        )

        guard OrbitMotion.allowsMotion(
            userEnabled: presentedAnimationsEnabled,
            reduceMotion: NSWorkspace.shared
                .accessibilityDisplayShouldReduceMotion
        )
        else {
            hoverMotions[index] = nil
            if isHovered {
                hoverScales[index] = motion.targetScale
            } else {
                hoverScales[index] = nil
            }
            renderArtwork()
            updateDisplayLinkState()
            return
        }

        hoverMotions[index] = motion
        updateDisplayLinkState()
    }

    /// Stop spatial motion immediately when macOS enables Reduce Motion.
    /// The final state and hover feedback remain visible, so animation is
    /// never the only carrier of information.
    private func accessibilityDisplayOptionsDidChange() {
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }

        pillMotion = nil
        transitionSourceIndex = nil
        hoverMotions.removeAll()
        hoverScales.removeAll()
        artworkRefreshMotion = nil
        artworkRefreshDidApplySettings = false
        artworkPresentation = .identity

        applyPendingVisualSettings()

        if let hoveredIndex,
           (0..<renderedSpaceCount).contains(hoveredIndex) {
            let hover = StatusHoverMotion(
                index: hoveredIndex,
                fromScale: CGSize(width: 1, height: 1),
                isHovered: true,
                isActive: hoveredIndex == renderedActiveIndex,
                startTime: CACurrentMediaTime()
            )
            hoverScales[hoveredIndex] = hover.targetScale
            renderArtwork()
        }
        updateDisplayLinkState()
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        guard presentedMenu == nil else { return }
        let menu = makeContextMenu()
        menu.delegate = self
        presentedMenu = menu
        statusItem.menu = menu

        // Let NSStatusItem perform its own menu tracking. AppKit then anchors
        // the complete menu below the status item and keeps its highlight for
        // exactly as long as the menu is open.
        DispatchQueue.main.async { [weak button] in
            button?.performClick(nil)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === presentedMenu else { return }
        statusItem.menu = nil
        presentedMenu = nil
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

        let settingsItem = item(
            "Настройки…",
            action: #selector(showSettings),
            symbol: "gearshape",
            key: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)
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

    @objc private func requestAccess() {
        _ = viewModel.requestEventPostingAccess()
    }

    @objc func showSettings() {
        let settingsWindowController = settingsWindowController
        DispatchQueue.main.async {
            settingsWindowController.show()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private var indicatorSizeScale: CGFloat {
        presentedSizeScale
    }

    private var indicatorSpacingScale: CGFloat {
        presentedSpacingScale
    }

    private var renderedItemWidth: CGFloat {
        StatusItemArtwork.itemWidth(
            sizeScale: indicatorSizeScale,
            spacingScale: indicatorSpacingScale
        )
    }

    private var renderedDesktopColorSlotCount: Int {
        max(
            renderedIndicatorKinds.map(\.colorIndex).max().map { $0 + 1 }
                ?? 1,
            1
        )
    }

    private func indicatorCenterX(for index: Int) -> CGFloat {
        StatusItemArtwork.centerX(
            for: index,
            sizeScale: indicatorSizeScale,
            spacingScale: indicatorSpacingScale
        )
    }

    private func refreshArtworkForSettings() {
        updateArtwork(
            for: renderedSpaceCount,
            indicatorKinds: renderedIndicatorKinds,
            force: true
        )
    }

    private func beginArtworkRefresh() {
        guard OrbitMotion.allowsMotion(
            userEnabled: settings.animateIndicator,
            reduceMotion: NSWorkspace.shared
                .accessibilityDisplayShouldReduceMotion
        ) else {
            applyPendingVisualSettings()
            return
        }

        pillMotion = nil
        transitionSourceIndex = nil
        hoverMotions.removeAll()
        artworkRefreshMotion = StatusArtworkRefreshMotion(
            startTime: CACurrentMediaTime(),
            initialPresentation: artworkPresentation
        )
        artworkRefreshDidApplySettings = false
        updateDisplayLinkState()
    }

    private func applyPendingVisualSettings() {
        presentedSizeScale = CGFloat(settings.indicatorSizeScale)
        presentedSpacingScale = CGFloat(settings.indicatorSpacingScale)
        presentedAnimationsEnabled = settings.animateIndicator
        presentedAnimationStyle = settings.indicatorAnimationStyle
        refreshArtworkForSettings()
    }
}
