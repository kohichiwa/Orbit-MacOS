import AppKit
import QuartzCore
import SwiftUI

/// The enlarged settings preview uses the same bitmap renderer and the same
/// display-link driven motion models as the menu-bar indicator. Keeping the
/// preview in this AppKit-backed view prevents SwiftUI's layout animation from
/// producing a different silhouette or timing curve.
@MainActor
struct DemoIndicatorArtwork: NSViewRepresentable {
    let indicators: [SpaceIndicatorKind]
    let colors: [NSColor]
    let activeIndex: Int
    let hoveredIndex: Int?
    let sizeScale: CGFloat
    let spacingScale: CGFloat
    let showsDarkEdge: Bool
    let shapeStyle: IndicatorShapeStyle
    let animationsEnabled: Bool
    let animationStyle: IndicatorAnimationStyle
    let reduceMotion: Bool
    let increasedContrast: Bool
    let applicationPreviewIndex: Int?
    let applicationPreviewApplications: [SpaceApplicationPresentation]
    let isApplicationPreviewPresented: Bool
    let onApplicationPreviewDismissed: @MainActor @Sendable () -> Void
    let onRenderedIndicatorOffsets:
        @MainActor @Sendable ([CGFloat]) -> Void

    func makeNSView(context: Context) -> SyncedIndicatorArtworkView {
        let view = SyncedIndicatorArtworkView()
        update(view)
        return view
    }

    func updateNSView(
        _ nsView: SyncedIndicatorArtworkView,
        context: Context
    ) {
        update(nsView)
    }

    static func dismantleNSView(
        _ nsView: SyncedIndicatorArtworkView,
        coordinator: Void
    ) {
        nsView.stopAnimations()
    }

    private func update(_ view: SyncedIndicatorArtworkView) {
        view.update(
            indicators: indicators,
            colors: colors,
            activeIndex: activeIndex,
            hoveredIndex: hoveredIndex,
            sizeScale: sizeScale,
            spacingScale: spacingScale,
            showsDarkEdge: showsDarkEdge,
            shapeStyle: shapeStyle,
            animationsEnabled: animationsEnabled,
            animationStyle: animationStyle,
            reduceMotion: reduceMotion,
            increasedContrast: increasedContrast,
            applicationPreviewIndex: applicationPreviewIndex,
            applicationPreviewApplications: applicationPreviewApplications,
            isApplicationPreviewPresented: isApplicationPreviewPresented,
            onApplicationPreviewDismissed: onApplicationPreviewDismissed,
            onRenderedIndicatorOffsets: onRenderedIndicatorOffsets
        )
    }
}

@MainActor
final class SyncedIndicatorArtworkView: NSView {
    private struct Configuration {
        let indicators: [SpaceIndicatorKind]
        let colors: [NSColor]
        let activeIndex: Int?
        let hoveredIndex: Int?
        let sizeScale: CGFloat
        let spacingScale: CGFloat
        let showsDarkEdge: Bool
        let shapeStyle: IndicatorShapeStyle
        let animationsEnabled: Bool
        let animationStyle: IndicatorAnimationStyle
        let reduceMotion: Bool
        let increasedContrast: Bool
    }

    private static let minimumPreviewHeight: CGFloat = 45

    static func previewHeight(for sizeScale: CGFloat) -> CGFloat {
        max(
            minimumPreviewHeight,
            StatusApplicationPreviewLayout.pillHeight
                * max(sizeScale, 0.01) + 2
        )
    }

    static func horizontalOverflowPadding(
        for sizeScale: CGFloat,
        spacingScale: CGFloat
    ) -> CGFloat {
        let maximumPillHalfWidth = StatusPillMotion.maximumWidthFactor
            * StatusHoverMotion.maximumHorizontalScale
            * sizeScale
            / 2
        let edgeIndicatorCenter = StatusItemArtwork.edgeItemWidth(
            sizeScale: sizeScale
        ) / 2
        let antialiasingAllowance = 0.75 * sizeScale
        return max(
            maximumPillHalfWidth - edgeIndicatorCenter,
            0
        ) + antialiasingAllowance
    }

    private var requestedConfiguration: Configuration?
    private var configuration: Configuration?
    private var pendingConfiguration: Configuration?
    private var renderer: StatusIndicatorImageRenderer?
    private var renderedActiveIndex: Int?
    private var renderedPillFrame: StatusPillFrame?
    private var pillMotion: StatusPillMotion?
    private var transitionSourceIndex: Int?
    private var interruptedTransitionPresentation:
        StatusInterruptedTransitionPresentation?
    private var hoveredIndex: Int?
    private var hoverScales: [Int: CGSize] = [:]
    private var hoverMotions: [Int: StatusHoverMotion] = [:]
    private var applicationPreviewIndex: Int?
    private var applicationPreviewApplications: [
        SpaceApplicationPresentation
    ] = []
    private var applicationPreviewFrame =
        StatusApplicationPreviewFrame.hidden
    private var applicationPreviewMotion: StatusApplicationPreviewMotion?
    private var applicationPreviewTracksPill = false
    private var onApplicationPreviewDismissed:
        (@MainActor @Sendable () -> Void)?
    private var onRenderedIndicatorOffsets:
        (@MainActor @Sendable ([CGFloat]) -> Void)?
    private var lastPublishedIndicatorOffsets: [CGFloat] = []
    private var artworkPresentation: StatusArtworkPresentation = .identity
    private var artworkRefreshMotion: StatusArtworkRefreshMotion?
    private var artworkRefreshDidApplySettings = false
    private var animationDisplayLink: CADisplayLink?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        publishRenderedIndicatorOffsets()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            configureDisplayLinkIfNeeded()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let renderer else { return }
        let origin = NSPoint(
            x: (bounds.width - renderer.imageSize.width) / 2,
            y: (bounds.height - renderer.imageSize.height) / 2
        )
        renderer.image.draw(
            at: origin,
            from: NSRect(origin: .zero, size: renderer.imageSize),
            operation: .sourceOver,
            fraction: 1
        )
    }

    func update(
        indicators: [SpaceIndicatorKind],
        colors: [NSColor],
        activeIndex: Int,
        hoveredIndex: Int?,
        sizeScale: CGFloat,
        spacingScale: CGFloat,
        showsDarkEdge: Bool,
        shapeStyle: IndicatorShapeStyle,
        animationsEnabled: Bool,
        animationStyle: IndicatorAnimationStyle,
        reduceMotion: Bool,
        increasedContrast: Bool,
        applicationPreviewIndex: Int?,
        applicationPreviewApplications: [SpaceApplicationPresentation],
        isApplicationPreviewPresented: Bool,
        onApplicationPreviewDismissed:
            @escaping @MainActor @Sendable () -> Void,
        onRenderedIndicatorOffsets:
            @escaping @MainActor @Sendable ([CGFloat]) -> Void
    ) {
        self.onApplicationPreviewDismissed =
            onApplicationPreviewDismissed
        self.onRenderedIndicatorOffsets = onRenderedIndicatorOffsets
        guard !indicators.isEmpty else {
            clearArtwork()
            return
        }
        defer {
            updateApplicationPreview(
                index: applicationPreviewIndex,
                applications: applicationPreviewApplications,
                isPresented: isApplicationPreviewPresented
            )
        }

        let normalizedActiveIndex = indicators.indices.contains(activeIndex)
            ? activeIndex
            : nil
        let normalizedHoveredIndex = hoveredIndex.flatMap {
            indicators.indices.contains($0) ? $0 : nil
        }
        let newConfiguration = Configuration(
            indicators: indicators,
            colors: colors,
            activeIndex: normalizedActiveIndex,
            hoveredIndex: normalizedHoveredIndex,
            sizeScale: sizeScale,
            spacingScale: spacingScale,
            showsDarkEdge: showsDarkEdge,
            shapeStyle: shapeStyle,
            animationsEnabled: animationsEnabled,
            animationStyle: animationStyle,
            reduceMotion: reduceMotion,
            increasedContrast: increasedContrast
        )
        let previousRequestedConfiguration = requestedConfiguration
        requestedConfiguration = newConfiguration

        guard let presentedConfiguration = configuration else {
            configuration = newConfiguration
            rebuildArtwork(
                for: newConfiguration,
                previousHoveredIndex: self.hoveredIndex
            )
            return
        }

        let comparisonConfiguration = previousRequestedConfiguration
            ?? presentedConfiguration
        if animatedConfigurationChanged(
            from: comparisonConfiguration,
            to: newConfiguration
        ) {
            beginArtworkRefresh(to: newConfiguration)
            return
        }

        if immediateConfigurationChanged(
            from: comparisonConfiguration,
            to: newConfiguration
        ) {
            pendingConfiguration = nil
            artworkRefreshMotion = nil
            artworkPresentation = .identity
            configuration = newConfiguration
            rebuildArtwork(
                for: newConfiguration,
                previousHoveredIndex: self.hoveredIndex
            )
            return
        }

        if artworkRefreshMotion != nil {
            pendingConfiguration = newConfiguration
        }

        let updatedPresentedConfiguration = Configuration(
            indicators: newConfiguration.indicators,
            colors: newConfiguration.colors,
            activeIndex: newConfiguration.activeIndex,
            hoveredIndex: newConfiguration.hoveredIndex,
            sizeScale: presentedConfiguration.sizeScale,
            spacingScale: presentedConfiguration.spacingScale,
            showsDarkEdge: newConfiguration.showsDarkEdge,
            shapeStyle: presentedConfiguration.shapeStyle,
            animationsEnabled: presentedConfiguration.animationsEnabled,
            animationStyle: presentedConfiguration.animationStyle,
            reduceMotion: newConfiguration.reduceMotion,
            increasedContrast: newConfiguration.increasedContrast
        )
        let artworkChanged = artworkContentChanged(
            from: presentedConfiguration,
            to: updatedPresentedConfiguration
        )
        let colorsChanged = !colorsAreEqual(
            presentedConfiguration.colors,
            updatedPresentedConfiguration.colors
        )
        let darkEdgeChanged =
            presentedConfiguration.showsDarkEdge
                != updatedPresentedConfiguration.showsDarkEdge
        configuration = updatedPresentedConfiguration

        if artworkChanged {
            beginArtworkRefresh(to: updatedPresentedConfiguration)
            return
        }
        var needsImmediateRender = false
        if colorsChanged {
            renderer?.setIndicatorColors(
                updatedPresentedConfiguration.colors
            )
            needsImmediateRender = true
        }
        if darkEdgeChanged {
            renderer?.setShowsDarkEdge(
                updatedPresentedConfiguration.showsDarkEdge
            )
            needsImmediateRender = true
        }
        if needsImmediateRender {
            renderArtwork()
        }
        if presentedConfiguration.activeIndex != normalizedActiveIndex {
            updateActivePill(to: normalizedActiveIndex, animated: true)
        }
        if presentedConfiguration.hoveredIndex != normalizedHoveredIndex {
            setHoveredIndex(normalizedHoveredIndex)
        }
    }

    func stopAnimations() {
        animationDisplayLink?.invalidate()
        animationDisplayLink = nil
        pillMotion = nil
        transitionSourceIndex = nil
        interruptedTransitionPresentation = nil
        hoverMotions.removeAll()
        artworkRefreshMotion = nil
        applicationPreviewMotion = nil
        applicationPreviewTracksPill = false
    }

    private func animatedConfigurationChanged(
        from old: Configuration,
        to new: Configuration
    ) -> Bool {
        old.animationsEnabled != new.animationsEnabled
            || old.animationStyle != new.animationStyle
            || old.shapeStyle != new.shapeStyle
    }

    private func immediateConfigurationChanged(
        from old: Configuration,
        to new: Configuration
    ) -> Bool {
        old.sizeScale != new.sizeScale
            || old.spacingScale != new.spacingScale
            || old.reduceMotion != new.reduceMotion
            || old.increasedContrast != new.increasedContrast
    }

    private func artworkContentChanged(
        from old: Configuration,
        to new: Configuration
    ) -> Bool {
        old.indicators != new.indicators
    }

    private func colorsAreEqual(
        _ lhs: [NSColor],
        _ rhs: [NSColor]
    ) -> Bool {
        lhs.count == rhs.count
            && zip(lhs, rhs).allSatisfy { $0.isEqual($1) }
    }

    private func beginArtworkRefresh(to newConfiguration: Configuration) {
        pendingConfiguration = newConfiguration

        guard OrbitMotion.allowsMotion(
            userEnabled: newConfiguration.animationsEnabled,
            reduceMotion: newConfiguration.reduceMotion
        ) else {
            artworkRefreshMotion = nil
            artworkPresentation = .identity
            configuration = newConfiguration
            rebuildArtwork(
                for: newConfiguration,
                previousHoveredIndex: hoveredIndex
            )
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
        configureDisplayLinkIfNeeded()
        updateDisplayLinkState()
    }

    private func applyPendingConfiguration() {
        guard let pendingConfiguration else { return }
        let previousHoveredIndex = hoveredIndex
        configuration = pendingConfiguration
        self.pendingConfiguration = nil
        rebuildArtwork(
            for: pendingConfiguration,
            previousHoveredIndex: previousHoveredIndex
        )
    }

    private func rebuildArtwork(
        for configuration: Configuration,
        previousHoveredIndex: Int?
    ) {
        pillMotion = nil
        transitionSourceIndex = nil
        interruptedTransitionPresentation = nil
        hoverMotions.removeAll()
        applicationPreviewTracksPill = false
        hoverScales = hoverScales.filter {
            configuration.indicators.indices.contains($0.key)
        }

        renderer = StatusIndicatorImageRenderer(
            count: configuration.indicators.count,
            indicatorKinds: configuration.indicators,
            indicatorColors: configuration.colors,
            showsDarkEdge: configuration.showsDarkEdge,
            shapeStyle: configuration.shapeStyle,
            sizeScale: configuration.sizeScale,
            spacingScale: configuration.spacingScale,
            imageHeight: Self.previewHeight(
                for: configuration.sizeScale
            ),
            horizontalOverflowPadding: Self.horizontalOverflowPadding(
                for: configuration.sizeScale,
                spacingScale: configuration.spacingScale
            ),
            increasedContrast: configuration.increasedContrast,
            applicationPreviewIndex: applicationPreviewIndex,
            applicationIcons: applicationPreviewApplications.map(\.icon),
            maximumApplicationPreviewIconCount:
                StatusApplicationPreviewLayout.maximumIconCount,
            maximumVisibleContentWidth:
                StatusApplicationPreviewLayout.demoMaximumContentWidth
        )
        renderedActiveIndex = configuration.activeIndex
        renderedPillFrame = configuration.activeIndex.map {
            .resting(
                at: indicatorCenterX(for: $0),
                sizeScale: configuration.sizeScale,
                shapeStyle: configuration.shapeStyle
            )
        }
        hoveredIndex = configuration.hoveredIndex
        renderArtwork()

        if let hoveredIndex = configuration.hoveredIndex,
           previousHoveredIndex != hoveredIndex
                || hoverScales[hoveredIndex] == nil {
            startHoverMotion(at: hoveredIndex, isHovered: true)
        }
        updateDisplayLinkState()
    }

    private func updateApplicationPreview(
        index: Int?,
        applications: [SpaceApplicationPresentation],
        isPresented: Bool
    ) {
        let normalizedApplications = Array(
            applications.prefix(
                StatusApplicationPreviewLayout.maximumIconCount
            )
        )
        let normalizedIndex = index.flatMap {
            configuration?.indicators.indices.contains($0) == true
                && !normalizedApplications.isEmpty
                ? $0
                : nil
        }
        let indexChanged = normalizedIndex != applicationPreviewIndex
        let applicationsChanged =
            normalizedApplications.map(\.visualIdentity)
                != applicationPreviewApplications.map(\.visualIdentity)

        if indexChanged {
            let canContinueCurrentPreview =
                normalizedIndex != nil
                    && applicationPreviewIndex != nil
                    && applicationPreviewFrame.expansion > 0.001
            applicationPreviewMotion = nil
            applicationPreviewTracksPill = false
            applicationPreviewFrame = canContinueCurrentPreview
                ? applicationPreviewFrame
                : .hidden
            applicationPreviewIndex = normalizedIndex
            applicationPreviewApplications = normalizedApplications
            renderer?.setApplicationPreview(
                index: normalizedIndex,
                icons: normalizedApplications.map(\.icon)
            )
            renderArtwork()
        } else if applicationsChanged {
            applicationPreviewApplications = normalizedApplications
            renderer?.setApplicationPreview(
                index: normalizedIndex,
                icons: normalizedApplications.map(\.icon)
            )
            renderArtwork()
        }

        guard isPresented, normalizedIndex != nil else {
            dismissApplicationPreview()
            return
        }
        guard
            applicationPreviewFrame != .visible
                || applicationPreviewMotion != nil,
            applicationPreviewMotion?.isPresenting != true
        else { return }
        startApplicationPreviewMotion(isPresenting: true)
    }

    private func dismissApplicationPreview() {
        guard applicationPreviewIndex != nil else { return }
        guard applicationPreviewMotion?.isPresenting != false else {
            return
        }
        if applicationPreviewFrame.expansion <= 0.001 {
            applicationPreviewFrame = .hidden
            applicationPreviewTracksPill = false
            applicationPreviewIndex = nil
            applicationPreviewApplications.removeAll()
            renderer?.setApplicationPreview(index: nil, icons: [])
            renderArtwork()
            notifyApplicationPreviewDismissed()
            return
        }
        startApplicationPreviewMotion(isPresenting: false)
    }

    private func startApplicationPreviewMotion(isPresenting: Bool) {
        guard let configuration else { return }
        if isPresenting {
            applicationPreviewTracksPill = false
        }
        guard OrbitMotion.allowsMotion(
            userEnabled: configuration.animationsEnabled,
            reduceMotion: configuration.reduceMotion
        ) else {
            applicationPreviewMotion = nil
            applicationPreviewFrame = isPresenting ? .visible : .hidden
            if !isPresenting {
                applicationPreviewTracksPill = false
                applicationPreviewIndex = nil
                applicationPreviewApplications.removeAll()
                renderer?.setApplicationPreview(index: nil, icons: [])
                notifyApplicationPreviewDismissed()
            }
            renderArtwork()
            return
        }
        applicationPreviewMotion = StatusApplicationPreviewMotion(
            isPresenting: isPresenting,
            fromFrame: applicationPreviewFrame,
            startTime: CACurrentMediaTime()
        )
        configureDisplayLinkIfNeeded()
        updateDisplayLinkState()
    }

    private func dismissApplicationPreviewImmediately() {
        guard applicationPreviewIndex != nil else {
            applicationPreviewTracksPill = false
            return
        }
        applicationPreviewMotion = nil
        applicationPreviewTracksPill = false
        applicationPreviewFrame = .hidden
        applicationPreviewIndex = nil
        applicationPreviewApplications.removeAll()
        renderer?.setApplicationPreview(index: nil, icons: [])
        notifyApplicationPreviewDismissed()
    }

    private func dismissApplicationPreviewForSpaceTransition(
        sourceActiveIndex: Int,
        startTime: TimeInterval,
        fullDuration: TimeInterval
    ) {
        guard let configuration else { return }
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
                userEnabled: configuration.animationsEnabled,
                reduceMotion: configuration.reduceMotion
            )
        guard allowsMotion else {
            dismissApplicationPreviewImmediately()
            return
        }

        applicationPreviewMotion = StatusApplicationPreviewMotion(
            isPresenting: false,
            fromFrame: applicationPreviewFrame,
            startTime: startTime,
            fullDuration: fullDuration
        )
        configureDisplayLinkIfNeeded()
        updateDisplayLinkState()
    }

    private func updateActivePill(to index: Int?, animated: Bool) {
        guard let configuration else { return }
        guard let index else {
            let previousIndex = renderedActiveIndex
            dismissApplicationPreviewImmediately()
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
                userEnabled: configuration.animationsEnabled,
                reduceMotion: configuration.reduceMotion
            )
        else {
            renderedActiveIndex = index
            if previousIndex != index {
                retargetHoveredIndicator()
            }
            if previousIndex != index {
                dismissApplicationPreviewImmediately()
            }
            stopPillMotion()
            renderedPillFrame = .resting(
                at: targetX,
                sizeScale: configuration.sizeScale,
                shapeStyle: configuration.shapeStyle
            )
            renderArtwork()
            return
        }

        let now = CACurrentMediaTime()
        let existingMotion = pillMotion
        // Retarget from the exact frame that draw(_:) has already shown.
        // Sampling the old trajectory at event time advances it by up to one
        // refresh interval and creates a visible skip during rapid reversals.
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
        let activeSize = configuration.shapeStyle.activeIndicatorSize(
            sizeScale: configuration.sizeScale
        )

        let interruptedPresentation: StatusInterruptedTransitionPresentation?
        let motion: StatusPillMotion

        if shouldRetargetFromCurrentFrame, let currentFrame {
            motion = .statusBarContinuation(
                from: currentFrame,
                toX: targetX,
                startTime: now,
                sizeScale: configuration.sizeScale,
                itemWidth: renderedItemWidth,
                shapeStyle: configuration.shapeStyle,
                style: configuration.animationStyle
            )
            interruptedPresentation = nil
        } else {
            interruptedPresentation = existingMotion.flatMap { _ in
                currentFrame.flatMap {
                    renderer?.transitionPresentationSnapshot(for: $0)
                }
            }
            motion = StatusPillMotion(
                fromX: sourceX,
                toX: targetX,
                initialWidth: currentFrame?.width
                    ?? activeSize.width,
                initialHeight: currentFrame?.height
                    ?? activeSize.height,
                initialWaist: currentFrame?.waist ?? 0,
                initialAppearanceProgress:
                    interruptedPresentation == nil && isReversing
                    ? 1 - (currentFrame?.progress ?? 0)
                    : 0,
                startTime: now,
                sizeScale: configuration.sizeScale,
                itemWidth: renderedItemWidth,
                style: configuration.animationStyle,
                shapeStyle: configuration.shapeStyle,
                isRetargeting: existingMotion != nil
            )
        }
        renderedActiveIndex = index
        dismissApplicationPreviewForSpaceTransition(
            sourceActiveIndex: previousIndex,
            startTime: now,
            fullDuration: motion.duration
        )
        transitionSourceIndex = configuration.animationStyle
            .blendsIndicatorAppearanceDuringTransition
            ? previousIndex
            : nil
        interruptedTransitionPresentation = interruptedPresentation
        pillMotion = motion
        renderedPillFrame = motion.frame(at: motion.startTime)
        if previousIndex != index {
            retargetHoveredIndicator()
        }
        renderArtwork()
        configureDisplayLinkIfNeeded()
        animationDisplayLink?.isPaused = false
    }

    private func setHoveredIndex(_ index: Int?) {
        guard index != hoveredIndex else { return }
        let previousIndex = hoveredIndex
        hoveredIndex = index

        if let previousIndex {
            startHoverMotion(at: previousIndex, isHovered: false)
        }
        if let index {
            startHoverMotion(at: index, isHovered: true)
        }
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
        guard let configuration else { return }
        let motion = StatusHoverMotion(
            index: index,
            fromScale: fromScale,
            isHovered: isHovered,
            isActive: index == renderedActiveIndex,
            startTime: now,
            shapeStyle: configuration.shapeStyle
        )

        guard OrbitMotion.allowsMotion(
            userEnabled: configuration.animationsEnabled,
            reduceMotion: configuration.reduceMotion
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
        configureDisplayLinkIfNeeded()
        updateDisplayLinkState()
    }

    private func motionIsNearRest(
        fromScale: CGSize,
        toScale: CGSize
    ) -> Bool {
        abs(fromScale.width - toScale.width) < 0.001
            && abs(fromScale.height - toScale.height) < 0.001
    }

    private func configureDisplayLinkIfNeeded() {
        guard animationDisplayLink == nil else { return }
        let link = displayLink(
            target: self,
            selector: #selector(advanceAnimations(_:))
        )
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: 120,
            preferred: 120
        )
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        animationDisplayLink = link
        updateDisplayLinkState()
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
                applyPendingConfiguration()
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
                    applicationPreviewFrame = .hidden
                    applicationPreviewTracksPill = false
                    applicationPreviewIndex = nil
                    applicationPreviewApplications.removeAll()
                    renderer?.setApplicationPreview(index: nil, icons: [])
                    notifyApplicationPreviewDismissed()
                }
            }
        }

        if needsRender {
            renderArtwork()
        }
        updateDisplayLinkState()
    }

    private func renderArtwork() {
        renderer?.update(
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
        publishRenderedIndicatorOffsets()
        needsDisplay = true
    }

    private func publishRenderedIndicatorOffsets() {
        guard
            let renderer,
            renderer.count > 0,
            bounds.width > 0
        else { return }
        let imageOriginX = (bounds.width - renderer.imageSize.width) / 2
        let offsets = (0..<renderer.count).compactMap { index in
            renderer.renderedIndicatorCenterX(at: index).map {
                imageOriginX + $0 - bounds.midX
            }
        }
        guard offsets.count == renderer.count else { return }
        guard offsets != lastPublishedIndicatorOffsets else { return }
        lastPublishedIndicatorOffsets = offsets
        onRenderedIndicatorOffsets?(offsets)
    }

    private func stopPillMotion() {
        pillMotion = nil
        transitionSourceIndex = nil
        interruptedTransitionPresentation = nil
        updateDisplayLinkState()
    }

    private func updateDisplayLinkState() {
        animationDisplayLink?.isPaused = pillMotion == nil
            && hoverMotions.isEmpty
            && artworkRefreshMotion == nil
            && applicationPreviewMotion == nil
    }

    private func indicatorCenterX(for index: Int) -> CGFloat {
        guard let configuration else { return 0 }
        return StatusItemArtwork.centerX(
            for: index,
            sizeScale: configuration.sizeScale,
            spacingScale: configuration.spacingScale
        )
    }

    private var renderedItemWidth: CGFloat {
        guard let configuration else { return StatusItemArtwork.itemWidth }
        return StatusItemArtwork.itemWidth(
            sizeScale: configuration.sizeScale,
            spacingScale: configuration.spacingScale
        )
    }

    private func clearArtwork() {
        requestedConfiguration = nil
        configuration = nil
        pendingConfiguration = nil
        renderer = nil
        renderedActiveIndex = nil
        renderedPillFrame = nil
        hoveredIndex = nil
        hoverScales.removeAll()
        applicationPreviewIndex = nil
        applicationPreviewApplications.removeAll()
        applicationPreviewFrame = .hidden
        applicationPreviewMotion = nil
        applicationPreviewTracksPill = false
        lastPublishedIndicatorOffsets.removeAll()
        artworkPresentation = .identity
        artworkRefreshDidApplySettings = false
        stopAnimations()
        needsDisplay = true
    }

    private func notifyApplicationPreviewDismissed() {
        guard let onApplicationPreviewDismissed else { return }
        DispatchQueue.main.async(execute: onApplicationPreviewDismissed)
    }
}
