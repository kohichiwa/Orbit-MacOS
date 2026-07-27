import AppKit
import Combine
import QuartzCore

enum StatusAccessibility {
    nonisolated static func value(
        for index: Int?,
        indicatorKinds: [SpaceIndicatorKind]
    ) -> String? {
        guard
            let index,
            indicatorKinds.indices.contains(index)
        else { return nil }
        let position = index + 1
        let total = indicatorKinds.count
        if indicatorKinds[index].isFullscreen {
            return OrbitL10n.format(
                "accessibility.status.fullscreen",
                fallback: "Полноэкранное приложение, %ld из %ld",
                position,
                total
            )
        }
        return OrbitL10n.format(
            "accessibility.status.desktop",
            fallback: "Рабочий стол %ld из %ld",
            position,
            total
        )
    }
}

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

    /// The status-bar button remains the click target; this view owns only
    /// the independent tracking area.
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
        // The status item's width and preview geometry can change during hover
        // and trigger transient exit events while the pointer is still over the
        // menu icon. Re-check the real pointer position to avoid flicker.
        eventHandler(nil)
    }
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private struct PendingArtworkStructure {
        let count: Int
        let indicatorKinds: [SpaceIndicatorKind]
    }

    private let viewModel: SpaceViewModel
    private let settings: AppSettings
    private let spaceApplicationReader: any SpaceApplicationReading
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables = Set<AnyCancellable>()
    private var renderedSpaceCount = 0
    private var renderedIndicatorKinds: [SpaceIndicatorKind] = []
    private var renderedActiveIndex: Int?
    private var renderedPillFrame: StatusPillFrame?
    private var artworkRenderer: StatusIndicatorImageRenderer?
    private var statusItemLength: CGFloat?
    private var displayLink: CADisplayLink?
    private var pillMotion: StatusPillMotion?
    private var transitionSourceIndex: Int?
    private var interruptedTransitionPresentation:
        StatusInterruptedTransitionPresentation?
    private var hoverTrackingView: StatusHoverTrackingView?
    private var globalMouseMonitor: Any?
    private var globalSpaceGestureMonitor: Any?
    private var hoveredIndex: Int?
    private var hoverScales: [Int: CGSize] = [:]
    private var hoverMotions: [Int: StatusHoverMotion] = [:]
    private var applicationPreviewTask: Task<Void, Never>?
    private var applicationPreviewIndex: Int?
    private var applicationPreviewApplications: [
        SpaceApplicationPresentation
    ] = []
    private var applicationPreviewFrame =
        StatusApplicationPreviewFrame.hidden
    private var applicationPreviewMotion: StatusApplicationPreviewMotion?
    private var applicationPreviewTracksPill = false
    private var artworkPresentation: StatusArtworkPresentation = .identity
    private var artworkRefreshMotion: StatusArtworkRefreshMotion?
    private var artworkRefreshDidApplySettings = false
    private var pendingArtworkStructure: PendingArtworkStructure?
    private var presentedSizeScale: CGFloat
    private var presentedSpacingScale: CGFloat
    private var presentedAnimationsEnabled: Bool
    private var presentedAnimationStyle: IndicatorAnimationStyle
    private var presentedShapeStyle: IndicatorShapeStyle
    private var presentedMenu: NSMenu?
    private var settingsWindowController: SettingsWindowController?
    private var isStopped = false

    init(
        viewModel: SpaceViewModel,
        settings: AppSettings,
        spaceApplicationReader: any SpaceApplicationReading =
            SystemSpaceApplicationReader()
    ) {
        self.viewModel = viewModel
        self.settings = settings
        self.spaceApplicationReader = spaceApplicationReader
        presentedSizeScale = CGFloat(settings.indicatorSizeScale)
        presentedSpacingScale = CGFloat(settings.indicatorSpacingScale)
        presentedAnimationsEnabled = settings.animateIndicator
        presentedAnimationStyle = settings.indicatorAnimationStyle
        presentedShapeStyle = settings.indicatorShapeStyle
        super.init()
        configureStatusItem()
        observeChanges()
        startGlobalSpaceGestureMonitoring()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true

        settingsWindowController?.stop()
        settingsWindowController = nil
        presentedMenu?.cancelTracking()
        presentedMenu = nil
        statusItem.menu = nil
        cancellables.removeAll()

        displayLink?.invalidate()
        displayLink = nil
        pillMotion = nil
        transitionSourceIndex = nil
        interruptedTransitionPresentation = nil
        hoverMotions.removeAll()
        artworkRefreshMotion = nil
        applicationPreviewTask?.cancel()
        applicationPreviewTask = nil
        applicationPreviewMotion = nil
        applicationPreviewTracksPill = false
        applicationPreviewApplications.removeAll()
        applicationPreviewIndex = nil

        stopGlobalMouseMonitoring()
        stopGlobalSpaceGestureMonitoring()
        hoverTrackingView?.removeFromSuperview()
        hoverTrackingView = nil
        statusItem.button?.target = nil
        statusItem.button?.action = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.focusRingType = .none
        button.imageScaling = .scaleNone
        button.contentTintColor = nil
        button.wantsLayer = true
        button.layer?.masksToBounds = true
        button.layer?.shadowOpacity = 0
        button.layer?.shadowRadius = 0
        button.layer?.shadowColor = nil
        button.layer?.borderWidth = 0
        button.layer?.borderColor = nil
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseDown])
        button.setAccessibilityLabel(
            OrbitL10n.text(
                "accessibility.orbitSpaces",
                fallback: "Пространства Orbit"
            )
        )

        updateArtwork(
            for: viewModel.spaceCount,
            indicatorKinds: viewModel.indicatorKinds
        )
        configureDisplayLink(for: button)
        configureHoverTracking(for: button)
        updateActivePill(to: viewModel.activeIndex, animated: false)
        updateAccessibilityValue(viewModel.activeIndex)
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

        settings.visualSettingsChanges
            .sink { [weak self] change in
                guard let self else { return }
                switch change {
                case .colors:
                    refreshIndicatorColors()
                case .outline:
                    refreshIndicatorEdge()
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
                case .shapeStyle:
                    beginArtworkRefresh()
                case .applicationsOnHover(let enabled):
                    if enabled, let hoveredIndex {
                        startHoverMotion(
                            at: hoveredIndex,
                            isHovered: false
                        )
                        scheduleApplicationPreview(for: hoveredIndex)
                    } else {
                        dismissApplicationPreview()
                        if let hoveredIndex {
                            startHoverMotion(
                                at: hoveredIndex,
                                isHovered: true
                            )
                        }
                    }
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

        NotificationCenter.default.publisher(
            for: NSColor.systemColorsDidChangeNotification
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshArtworkForSettings()
            }
            .store(in: &cancellables)
    }

    private func refreshIndicatorColors() {
        guard let artworkRenderer else { return }
        artworkRenderer.setIndicatorColors(
            settings.indicatorColors(
                for: renderedDesktopColorSlotCount
            )
        )
        renderArtwork()
    }

    private func refreshIndicatorEdge() {
        guard let artworkRenderer else { return }
        artworkRenderer.setShowsDarkEdge(
            settings.showsIndicatorOutline
        )
        renderArtwork()
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
                // AppKit can emit a transient exit while an NSStatusItem is
                // changing width. Re-read the actual pointer position after
                // that layout pass instead of collapsing a preview that is
                // still under the cursor.
                DispatchQueue.main.async { [weak self, weak button] in
                    guard let self, let button else { return }
                    self.synchronizeHoverLocation(for: button)
                }
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
        let structureChanged = count != renderedSpaceCount
            || indicatorKinds != renderedIndicatorKinds
        guard
            force
                || structureChanged
        else { return }
        if structureChanged,
           !force,
           renderedSpaceCount > 0,
           OrbitMotion.allowsMotion(
                userEnabled: presentedAnimationsEnabled,
                reduceMotion: NSWorkspace.shared
                    .accessibilityDisplayShouldReduceMotion
           ) {
            pendingArtworkStructure = PendingArtworkStructure(
                count: count,
                indicatorKinds: indicatorKinds
            )
            if artworkRefreshMotion == nil {
                beginStructureRefresh()
            }
            return
        }
        if structureChanged {
            applicationPreviewTask?.cancel()
            applicationPreviewTask = nil
            applicationPreviewIndex = nil
            applicationPreviewApplications.removeAll()
            applicationPreviewFrame = .hidden
            applicationPreviewMotion = nil
            applicationPreviewTracksPill = false
        }
        renderedSpaceCount = count
        renderedIndicatorKinds = indicatorKinds
        // A renderer rebuild establishes a new coordinate system. A motion
        // created by the previous renderer must never resume on its next
        // display-link tick, because its positions and shape metrics no longer
        // describe the pixels now on screen.
        pillMotion = nil
        transitionSourceIndex = nil
        interruptedTransitionPresentation = nil
        if let hoveredIndex, !(0..<count).contains(hoveredIndex) {
            self.hoveredIndex = nil
        }
        hoverScales = hoverScales.filter { (0..<count).contains($0.key) }
        hoverMotions = hoverMotions.filter { (0..<count).contains($0.key) }

        guard let button = statusItem.button else { return }

        let renderer = StatusIndicatorImageRenderer(
            count: count,
            indicatorKinds: indicatorKinds,
            indicatorColors: settings.indicatorColors(
                for: renderedDesktopColorSlotCount
            ),
            showsDarkEdge: settings.showsIndicatorOutline,
            shapeStyle: presentedShapeStyle,
            sizeScale: indicatorSizeScale,
            spacingScale: indicatorSpacingScale,
            horizontalOverflowPadding: StatusItemArtwork.horizontalPadding(
                sizeScale: indicatorSizeScale
            ),
            increasedContrast: NSWorkspace.shared
                .accessibilityDisplayShouldIncreaseContrast,
            applicationPreviewIndex: applicationPreviewIndex,
            applicationIcons: applicationPreviewApplications.map(\.icon),
            maximumApplicationPreviewIconCount:
                StatusApplicationPreviewLayout.maximumIconCount,
            maximumVisibleContentWidth:
                StatusItemArtwork.maximumStatusItemWidth
        )
        artworkRenderer = renderer

        statusItem.length = StatusItemArtwork.preferredWidth(
            for: count,
            sizeScale: indicatorSizeScale,
            spacingScale: indicatorSpacingScale
        )
        statusItemLength = statusItem.length

        button.image = renderer.image
        button.contentTintColor = nil

        if let index = viewModel.activeIndex, (0..<count).contains(index) {
            transitionSourceIndex = nil
            interruptedTransitionPresentation = nil
            renderedActiveIndex = index
            renderPill(
                .resting(
                    at: indicatorCenterX(for: index),
                    sizeScale: indicatorSizeScale,
                    shapeStyle: presentedShapeStyle
                )
            )
        } else {
            transitionSourceIndex = nil
            interruptedTransitionPresentation = nil
            renderedActiveIndex = nil
            renderedPillFrame = nil
            renderArtwork()
        }

        if hoverTrackingView != nil {
            configureHoverTracking(for: button)
        }
        updateAccessibilityValue(renderedActiveIndex)
        updateDisplayLinkState()
    }

    private func updateActivePill(to index: Int?, animated: Bool) {
        guard
            let index,
            (0..<renderedSpaceCount).contains(index)
        else {
            let previousIndex = renderedActiveIndex
            dismissApplicationPreview(
                animated: false,
                renderImmediately: false
            )
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
            renderedActiveIndex = index
            if previousIndex != index {
                retargetHoveredIndicator()
            }
            if previousIndex != index {
                dismissApplicationPreview(
                    animated: false,
                    renderImmediately: false
                )
            }
            stopPillMotion()
            renderPill(
                .resting(
                    at: targetX,
                    sizeScale: indicatorSizeScale,
                    shapeStyle: presentedShapeStyle
                )
            )
            return
        }

        let existingMotion = pillMotion
        let now = CACurrentMediaTime()
        let currentFrame = renderedPillFrame
            ?? existingMotion?.frame(at: now)
        let shouldRetargetFromCurrentFrame =
            existingMotion != nil
            && !(renderedPillFrame?.isComplete == true)
        let isReversing = existingMotion.map { motion in
            abs(motion.fromX - targetX) < 0.6
        } ?? false
        let sourceX = existingMotion == nil
            ? indicatorCenterX(for: previousIndex)
            : currentFrame?.x ?? indicatorCenterX(for: previousIndex)
        let activeSize = presentedShapeStyle.activeIndicatorSize(
            sizeScale: indicatorSizeScale
        )

        let interruptedPresentation: StatusInterruptedTransitionPresentation?
        let motion: StatusPillMotion
        
        if shouldRetargetFromCurrentFrame, let currentFrame {
            motion = .statusBarContinuation(
                from: currentFrame,
                toX: targetX,
                startTime: now,
                sizeScale: indicatorSizeScale,
                itemWidth: renderedItemWidth,
                shapeStyle: presentedShapeStyle,
                style: presentedAnimationStyle
            )
            interruptedPresentation = nil
        } else {
            interruptedPresentation = existingMotion.flatMap { _ in
                currentFrame.flatMap {
                    artworkRenderer?.transitionPresentationSnapshot(for: $0)
                }
            }
            motion = StatusPillMotion(
                fromX: sourceX,
                toX: targetX,
                initialWidth: currentFrame?.width ?? activeSize.width,
                initialHeight: currentFrame?.height ?? activeSize.height,
                initialWaist: currentFrame?.waist ?? 0,
                initialAppearanceProgress:
                    interruptedPresentation == nil && isReversing
                    ? 1 - (currentFrame?.progress ?? 0)
                    : 0,
                startTime: now,
                sizeScale: indicatorSizeScale,
                itemWidth: renderedItemWidth,
                style: presentedAnimationStyle,
                shapeStyle: presentedShapeStyle,
                isRetargeting: existingMotion != nil
            )
        }
        renderedActiveIndex = index
        dismissApplicationPreviewForSpaceTransition(
            sourceActiveIndex: previousIndex,
            startTime: now,
            fullDuration: motion.duration
        )
        transitionSourceIndex = presentedAnimationStyle
            .blendsIndicatorAppearanceDuringTransition
            ? previousIndex
            : nil
        interruptedTransitionPresentation = interruptedPresentation
        pillMotion = motion
        renderPill(motion.frame(at: motion.startTime))
        if previousIndex != index {
            retargetHoveredIndicator()
        }
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
                if let pendingArtworkStructure {
                    self.pendingArtworkStructure = nil
                    updateArtwork(
                        for: pendingArtworkStructure.count,
                        indicatorKinds:
                            pendingArtworkStructure.indicatorKinds,
                        force: true
                    )
                }
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
                interruptedTransitionPresentation = nil
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

        if let applicationPreviewMotion {
            let frame = applicationPreviewMotion.frame(at: timestamp)
            applicationPreviewFrame = frame
            needsRender = true
            if frame.isComplete {
                self.applicationPreviewMotion = nil
                if applicationPreviewMotion.isPresenting {
                    applicationPreviewFrame = .visible
                } else {
                    let shouldResumeForCurrentHover =
                        applicationPreviewTask == nil
                            && settings.showsApplicationsOnHover
                            && hoveredIndex != nil
                    applicationPreviewFrame = .hidden
                    applicationPreviewTracksPill = false
                    applicationPreviewIndex = nil
                    applicationPreviewApplications.removeAll()
                    artworkRenderer?.setApplicationPreview(
                        index: nil,
                        icons: []
                    )
                    if shouldResumeForCurrentHover {
                        resumeApplicationPreviewForCurrentHover()
                    }
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
            interruptedTransitionPresentation:
                interruptedTransitionPresentation,
            hoverScales: hoverScales,
            presentation: artworkPresentation,
            applicationPreviewFrame: applicationPreviewFrame,
            applicationPreviewTracksPill:
                applicationPreviewTracksPill
        )
        if let artworkRenderer {
            let desiredLength = artworkRenderer.currentStatusItemWidth
            if abs(desiredLength - (statusItemLength ?? 0)) > 0.01 {
                statusItem.length = desiredLength
                statusItemLength = desiredLength
            }
        }
        statusItem.button?.needsDisplay = true
    }

    private func stopPillMotion() {
        pillMotion = nil
        transitionSourceIndex = nil
        interruptedTransitionPresentation = nil
        updateDisplayLinkState()
    }

    private func updateDisplayLinkState() {
        displayLink?.isPaused = pillMotion == nil
            && hoverMotions.isEmpty
            && artworkRefreshMotion == nil
            && applicationPreviewMotion == nil
    }

    private func updateAccessibilityValue(_ index: Int?) {
        statusItem.button?.setAccessibilityValue(
            StatusAccessibility.value(
                for: index,
                indicatorKinds: renderedIndicatorKinds
            )
        )
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
        if let artworkRenderer {
            let imageX = point.x
                + (artworkRenderer.imageSize.width - button.bounds.width) / 2
            return artworkRenderer.indicatorIndex(atImageX: imageX)
        }
        let contentWidth = StatusItemArtwork.contentWidth(
            for: renderedSpaceCount,
            sizeScale: indicatorSizeScale,
            spacingScale: indicatorSpacingScale
        )
        let leadingEdge = max((button.bounds.width - contentWidth) / 2, 0)
        let relativeX = point.x - leadingEdge
        guard relativeX >= 0, relativeX < contentWidth else { return nil }
        let edgeHalfWidth = StatusItemArtwork.edgeItemWidth(
            sizeScale: indicatorSizeScale
        ) / 2
        let index = Int(floor(
            (relativeX - edgeHalfWidth + renderedItemWidth / 2)
                / renderedItemWidth
        ))
        return (0..<renderedSpaceCount).contains(index) ? index : nil
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
        let windowPoint = window.convertPoint(
            fromScreen: NSEvent.mouseLocation
        )
        let point = button.convert(
            windowPoint,
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

        if normalizedIndex != nil {
            startGlobalMouseMonitoringIfNeeded()
        } else {
            stopGlobalMouseMonitoring()
        }

        if let previousIndex {
            startHoverMotion(at: previousIndex, isHovered: false)
        }
        if let normalizedIndex {
            if settings.showsApplicationsOnHover {
                scheduleApplicationPreview(for: normalizedIndex)
            } else {
                startHoverMotion(at: normalizedIndex, isHovered: true)
            }
        } else {
            dismissApplicationPreview()
        }
    }

    private func startGlobalMouseMonitoringIfNeeded() {
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard
                    let self,
                    self.hoveredIndex != nil,
                    let button = self.statusItem.button
                else { return }
                self.synchronizeHoverLocation(for: button)
            }
        }
    }

    private func stopGlobalMouseMonitoring() {
        guard let globalMouseMonitor else { return }
        NSEvent.removeMonitor(globalMouseMonitor)
        self.globalMouseMonitor = nil
    }

    /// WindowServer freezes a bitmap of every status item while an
    /// interactive Space gesture is in progress. Leaving the pill halfway
    /// through a liquid morph at that instant makes the frozen bitmap look
    /// like a stalled Orbit animation and produces a jump when macOS swaps in
    /// the live menu bar again. Settle before the system captures that bitmap.
    private func startGlobalSpaceGestureMonitoring() {
        guard globalSpaceGestureMonitor == nil else { return }
        globalSpaceGestureMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.gesture, .swipe, .scrollWheel]
        ) { [weak self] event in
            let isHorizontalSpaceGesture: Bool
            if event.type == .scrollWheel {
                isHorizontalSpaceGesture =
                    abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                    && abs(event.scrollingDeltaX) > 0.01
            } else {
                isHorizontalSpaceGesture = true
            }
            guard isHorizontalSpaceGesture else { return }
            Task { @MainActor [weak self] in
                self?.settlePillBeforeSystemSpaceSnapshot()
            }
        }
    }

    private func stopGlobalSpaceGestureMonitoring() {
        guard let globalSpaceGestureMonitor else { return }
        NSEvent.removeMonitor(globalSpaceGestureMonitor)
        self.globalSpaceGestureMonitor = nil
    }

    private func settlePillBeforeSystemSpaceSnapshot() {
        guard
            pillMotion != nil,
            let renderedActiveIndex,
            (0..<renderedSpaceCount).contains(renderedActiveIndex)
        else { return }

        pillMotion = nil
        transitionSourceIndex = nil
        interruptedTransitionPresentation = nil
        renderedPillFrame = .resting(
            at: indicatorCenterX(for: renderedActiveIndex),
            sizeScale: indicatorSizeScale,
            shapeStyle: presentedShapeStyle
        )
        renderArtwork()
        updateDisplayLinkState()
    }

    private func scheduleApplicationPreview(for index: Int) {
        applicationPreviewTask?.cancel()
        applicationPreviewTask = nil

        guard
            settings.showsApplicationsOnHover,
            !applicationPreviewTracksPill,
            viewModel.indicators.indices.contains(index),
            renderedIndicatorKinds.indices.contains(index)
        else { return }

        // If the pointer returns while this same preview is closing, reverse
        // the in-flight motion from its current frame. The fresh lookup still
        // runs below, so continuity never comes at the cost of stale data.
        let continuesCurrentPreview = applicationPreviewIndex == index
            && !applicationPreviewApplications.isEmpty
            && applicationPreviewFrame.expansion > 0.001
        if continuesCurrentPreview {
            presentApplicationPreview(
                applications: applicationPreviewApplications,
                at: index
            )
        }

        let previousPreviewIndex = applicationPreviewIndex
        if previousPreviewIndex != nil,
           previousPreviewIndex != index {
            dismissApplicationPreview()
        }
        let now = CACurrentMediaTime()
        var presentationNotBefore = continuesCurrentPreview
            ? now
            : now + OrbitMotion.applicationPreviewHoverDelay
        if let applicationPreviewMotion,
           !applicationPreviewMotion.isPresenting {
            presentationNotBefore = max(
                presentationNotBefore,
                applicationPreviewMotion.startTime
                    + applicationPreviewMotion.duration
            )
        }
        let spaceIdentifier = viewModel.indicators[index].id
        let indicatorKind = renderedIndicatorKinds[index]
        let reader = spaceApplicationReader

        applicationPreviewTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let initialDelay = presentationNotBefore
                - CACurrentMediaTime()
            if initialDelay > 0 {
                try? await Task.sleep(
                    for: .seconds(initialDelay)
                )
            }

            while !Task.isCancelled {
                guard
                    self.settings.showsApplicationsOnHover,
                    self.hoveredIndex == index,
                    self.viewModel.indicators.indices.contains(index),
                    self.viewModel.indicators[index].id == spaceIdentifier
                else { return }

                // Read after the hover dwell rather than before it. A window
                // moved between Spaces immediately before hover is therefore
                // reflected by the snapshot that is actually presented.
                let processIdentifiers =
                    await reader.applicationProcessIdentifiers(
                        in: spaceIdentifier
                    )
                guard
                    !Task.isCancelled,
                    self.settings.showsApplicationsOnHover,
                    self.hoveredIndex == index
                else { return }

                let presentations =
                    SpaceApplicationPresentationFactory.presentations(
                        for: processIdentifiers,
                        maximumCount: indicatorKind.isFullscreen
                            ? 1
                            : StatusApplicationPreviewLayout.maximumIconCount
                    )
                guard !presentations.isEmpty else {
                    self.dismissApplicationPreview(animated: false)
                    self.startHoverMotion(at: index, isHovered: true)
                    return
                }
                self.presentApplicationPreview(
                    applications: presentations,
                    at: index
                )

                try? await Task.sleep(
                    for: .seconds(
                        OrbitMotion.applicationPreviewRefreshInterval
                    )
                )
            }
        }
    }

    private func resumeApplicationPreviewForCurrentHover() {
        guard
            pillMotion == nil,
            applicationPreviewTask == nil,
            let hoveredIndex,
            (0..<renderedSpaceCount).contains(hoveredIndex)
        else { return }
        scheduleApplicationPreview(for: hoveredIndex)
    }

    private func presentApplicationPreview(
        applications: [SpaceApplicationPresentation],
        at index: Int
    ) {
        guard
            settings.showsApplicationsOnHover,
            hoveredIndex == index,
            !applications.isEmpty
        else { return }

        let isCurrentPreview = applicationPreviewIndex == index
            && !applicationPreviewApplications.isEmpty
        let contentChanged = !isCurrentPreview
            || applications.map(\.visualIdentity)
                != applicationPreviewApplications.map(\.visualIdentity)

        if applicationPreviewIndex == index,
           applicationPreviewFrame == .visible,
           applicationPreviewMotion == nil {
            guard contentChanged else { return }
            applicationPreviewApplications = applications
            artworkRenderer?.setApplicationPreview(
                index: index,
                icons: applications.map(\.icon)
            )
            renderArtwork()
            return
        }

        let initialFrame =
            isCurrentPreview
                || (applicationPreviewIndex != nil
                    && applicationPreviewFrame.expansion > 0.001)
            ? applicationPreviewFrame
            : .hidden

        applicationPreviewIndex = index
        applicationPreviewApplications = applications
        applicationPreviewFrame = initialFrame
        applicationPreviewMotion = nil
        applicationPreviewTracksPill = false
        artworkRenderer?.setApplicationPreview(
            index: index,
            icons: applications.map(\.icon)
        )

        guard OrbitMotion.allowsMotion(
            userEnabled: presentedAnimationsEnabled,
            reduceMotion: NSWorkspace.shared
                .accessibilityDisplayShouldReduceMotion
        ) else {
            applicationPreviewFrame = .visible
            renderArtwork()
            return
        }

        applicationPreviewMotion = StatusApplicationPreviewMotion(
            isPresenting: true,
            fromFrame: initialFrame,
            startTime: CACurrentMediaTime()
        )
        renderArtwork()
        updateDisplayLinkState()
    }

    private func dismissApplicationPreview(
        animated: Bool = true,
        renderImmediately: Bool = true
    ) {
        applicationPreviewTask?.cancel()
        applicationPreviewTask = nil
        guard applicationPreviewIndex != nil else { return }
        guard
            !animated || applicationPreviewMotion?.isPresenting != false
        else {
            return
        }

        let allowsMotion = animated
            && applicationPreviewFrame.expansion > 0.001
            && OrbitMotion.allowsMotion(
                userEnabled: presentedAnimationsEnabled,
                reduceMotion: NSWorkspace.shared
                    .accessibilityDisplayShouldReduceMotion
            )
        guard allowsMotion else {
            applicationPreviewMotion = nil
            applicationPreviewTracksPill = false
            applicationPreviewFrame = .hidden
            applicationPreviewIndex = nil
            applicationPreviewApplications.removeAll()
            artworkRenderer?.setApplicationPreview(
                index: nil,
                icons: []
            )
            if renderImmediately {
                renderArtwork()
            }
            return
        }

        applicationPreviewMotion = StatusApplicationPreviewMotion(
            isPresenting: false,
            fromFrame: applicationPreviewFrame,
            startTime: CACurrentMediaTime()
        )
        if renderImmediately {
            renderArtwork()
        }
        updateDisplayLinkState()
    }

    /// A Space change must not leave the expanded application pill behind
    /// while the active pill starts a separate trip. When the preview belongs
    /// to the active Space, its current pixels travel with the pill and shrink
    /// on the exact same timeline. This keeps rapid swipe reversals
    /// interruptible without introducing a duplicate source pill.
    private func dismissApplicationPreviewForSpaceTransition(
        sourceActiveIndex: Int,
        startTime: TimeInterval,
        fullDuration: TimeInterval
    ) {
        applicationPreviewTask?.cancel()
        applicationPreviewTask = nil
        guard applicationPreviewIndex != nil else {
            applicationPreviewTracksPill = false
            return
        }

        applicationPreviewTracksPill =
            applicationPreviewTracksPill
                || applicationPreviewIndex == sourceActiveIndex
        let allowsMotion =
            applicationPreviewFrame.expansion > 0.001
            && OrbitMotion.allowsMotion(
                userEnabled: presentedAnimationsEnabled,
                reduceMotion: NSWorkspace.shared
                    .accessibilityDisplayShouldReduceMotion
            )
        guard allowsMotion else {
            applicationPreviewMotion = nil
            applicationPreviewTracksPill = false
            applicationPreviewFrame = .hidden
            applicationPreviewIndex = nil
            applicationPreviewApplications.removeAll()
            artworkRenderer?.setApplicationPreview(
                index: nil,
                icons: []
            )
            return
        }

        applicationPreviewMotion = StatusApplicationPreviewMotion(
            isPresenting: false,
            fromFrame: applicationPreviewFrame,
            startTime: startTime,
            fullDuration: fullDuration
        )
    }

    private func retargetHoveredIndicator() {
        guard let hoveredIndex else { return }
        startHoverMotion(at: hoveredIndex, isHovered: true)
    }

    private func startHoverMotion(at index: Int, isHovered: Bool) {
        let now = CACurrentMediaTime()
        let fromScale = hoverScales[index]
            ?? (hoverMotions[index].flatMap {
                $0.frame(at: now).scale
            } ?? CGSize(width: 1, height: 1))
        let motion = StatusHoverMotion(
            index: index,
            fromScale: fromScale,
            isHovered: isHovered,
            isActive: index == renderedActiveIndex,
            startTime: now,
            shapeStyle: presentedShapeStyle
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

        if motionIsNearRest(
            fromScale: fromScale,
            toScale: motion.targetScale
        ) {
            if isHovered {
                hoverScales[index] = motion.targetScale
            } else {
                hoverScales[index] = nil
            }
            hoverMotions[index] = nil
            renderArtwork()
            updateDisplayLinkState()
            return
        }

        hoverMotions[index] = motion
        updateDisplayLinkState()
    }

    private func motionIsNearRest(
        fromScale: CGSize,
        toScale: CGSize
    ) -> Bool {
        abs(fromScale.width - toScale.width) < 0.001
            && abs(fromScale.height - toScale.height) < 0.001
    }

    /// Stop spatial motion immediately when macOS enables Reduce Motion.
    /// The final state and hover feedback remain visible, so animation is
    /// never the only carrier of information.
    private func accessibilityDisplayOptionsDidChange() {
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            refreshArtworkForSettings()
            return
        }

        pillMotion = nil
        transitionSourceIndex = nil
        interruptedTransitionPresentation = nil
        hoverMotions.removeAll()
        hoverScales.removeAll()
        artworkRefreshMotion = nil
        artworkRefreshDidApplySettings = false
        artworkPresentation = .identity
        if let applicationPreviewMotion {
            if applicationPreviewMotion.isPresenting {
                applicationPreviewFrame = .visible
            } else {
                applicationPreviewFrame = .hidden
                applicationPreviewTracksPill = false
                applicationPreviewIndex = nil
                applicationPreviewApplications.removeAll()
            }
            self.applicationPreviewMotion = nil
        }

        applyPendingVisualSettings()

        if let hoveredIndex,
           (0..<renderedSpaceCount).contains(hoveredIndex) {
            let hover = StatusHoverMotion(
                index: hoveredIndex,
                fromScale: CGSize(width: 1, height: 1),
                isHovered: true,
                isActive: hoveredIndex == renderedActiveIndex,
                startTime: CACurrentMediaTime(),
                shapeStyle: presentedShapeStyle
            )
            hoverScales[hoveredIndex] = hover.targetScale
            renderArtwork()
        }
        updateDisplayLinkState()
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        guard presentedMenu == nil else { return }
        setHoveredIndex(nil)
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
        if let button = statusItem.button {
            synchronizeHoverLocation(for: button)
        }
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
            OrbitL10n.text("menu.settings", fallback: "Настройки…"),
            action: #selector(showSettings),
            symbol: "gearshape",
            key: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)
        if !viewModel.canPostEvents {
            menu.addItem(
                item(
                    OrbitL10n.text(
                        "menu.allowControl",
                        fallback: "Разрешить управление…"
                    ),
                    action: #selector(requestAccess),
                    symbol: "hand.raised"
                )
            )
        }
        menu.addItem(.separator())
        menu.addItem(
            item(
                OrbitL10n.text(
                    "menu.quit",
                    fallback: "Завершить Orbit"
                ),
                action: #selector(quit),
                symbol: "power",
                key: "q"
            )
        )
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
        let settingsWindowController: SettingsWindowController
        if let existingController = self.settingsWindowController {
            settingsWindowController = existingController
        } else {
            let newController = SettingsWindowController(
                settings: settings,
                viewModel: viewModel,
                spaceApplicationReader: spaceApplicationReader
            )
            self.settingsWindowController = newController
            settingsWindowController = newController
        }
        DispatchQueue.main.async {
            settingsWindowController.show()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private var indicatorSizeScale: CGFloat {
        StatusItemArtwork.fittedSizeScale(
            for: renderedSpaceCount,
            requestedSizeScale: presentedSizeScale,
            spacingScale: presentedSpacingScale
        )
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
        interruptedTransitionPresentation = nil
        hoverMotions.removeAll()
        artworkRefreshMotion = StatusArtworkRefreshMotion(
            startTime: CACurrentMediaTime(),
            initialPresentation: artworkPresentation
        )
        artworkRefreshDidApplySettings = false
        updateDisplayLinkState()
    }

    private func beginStructureRefresh() {
        pillMotion = nil
        transitionSourceIndex = nil
        interruptedTransitionPresentation = nil
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
        presentedShapeStyle = settings.indicatorShapeStyle
        refreshArtworkForSettings()
    }
}
