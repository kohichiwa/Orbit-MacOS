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
    let showsThinOutline: Bool
    let shapeStyle: IndicatorShapeStyle
    let animationsEnabled: Bool
    let animationStyle: IndicatorAnimationStyle
    let reduceMotion: Bool

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
            showsThinOutline: showsThinOutline,
            shapeStyle: shapeStyle,
            animationsEnabled: animationsEnabled,
            animationStyle: animationStyle,
            reduceMotion: reduceMotion
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
        let showsThinOutline: Bool
        let shapeStyle: IndicatorShapeStyle
        let animationsEnabled: Bool
        let animationStyle: IndicatorAnimationStyle
        let reduceMotion: Bool
    }

    private static let previewHeight: CGFloat = 45

    static func horizontalOverflowPadding(
        for sizeScale: CGFloat,
        spacingScale: CGFloat
    ) -> CGFloat {
        let maximumPillHalfWidth = StatusPillMotion.maximumWidthFactor
            * StatusHoverMotion.maximumHorizontalScale
            * sizeScale
            / 2
        let edgeIndicatorCenter = StatusItemArtwork.itemWidth(
            sizeScale: sizeScale,
            spacingScale: spacingScale
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
    private var hoveredIndex: Int?
    private var hoverScales: [Int: CGSize] = [:]
    private var hoverMotions: [Int: StatusHoverMotion] = [:]
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
        showsThinOutline: Bool,
        shapeStyle: IndicatorShapeStyle,
        animationsEnabled: Bool,
        animationStyle: IndicatorAnimationStyle,
        reduceMotion: Bool
    ) {
        guard !indicators.isEmpty else {
            clearArtwork()
            return
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
            showsThinOutline: showsThinOutline,
            shapeStyle: shapeStyle,
            animationsEnabled: animationsEnabled,
            animationStyle: animationStyle,
            reduceMotion: reduceMotion
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
            showsThinOutline: newConfiguration.showsThinOutline,
            shapeStyle: presentedConfiguration.shapeStyle,
            animationsEnabled: presentedConfiguration.animationsEnabled,
            animationStyle: presentedConfiguration.animationStyle,
            reduceMotion: newConfiguration.reduceMotion
        )
        let artworkChanged = artworkContentChanged(
            from: presentedConfiguration,
            to: updatedPresentedConfiguration
        )
        configuration = updatedPresentedConfiguration

        if artworkChanged {
            rebuildArtwork(
                for: updatedPresentedConfiguration,
                previousHoveredIndex: self.hoveredIndex
            )
            return
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
        hoverMotions.removeAll()
        artworkRefreshMotion = nil
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
            || old.showsThinOutline != new.showsThinOutline
            || old.reduceMotion != new.reduceMotion
    }

    private func artworkContentChanged(
        from old: Configuration,
        to new: Configuration
    ) -> Bool {
        old.indicators != new.indicators
            || !colorsAreEqual(old.colors, new.colors)
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
        hoverMotions.removeAll()
        hoverScales = hoverScales.filter {
            configuration.indicators.indices.contains($0.key)
        }

        renderer = StatusIndicatorImageRenderer(
            count: configuration.indicators.count,
            indicatorKinds: configuration.indicators,
            indicatorColors: configuration.colors,
            showsThinOutline: configuration.showsThinOutline,
            shapeStyle: configuration.shapeStyle,
            sizeScale: configuration.sizeScale,
            spacingScale: configuration.spacingScale,
            imageHeight: Self.previewHeight,
            horizontalOverflowPadding: Self.horizontalOverflowPadding(
                for: configuration.sizeScale,
                spacingScale: configuration.spacingScale
            )
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

    private func updateActivePill(to index: Int?, animated: Bool) {
        guard let configuration else { return }
        guard let index else {
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
                userEnabled: configuration.animationsEnabled,
                reduceMotion: configuration.reduceMotion
            )
        else {
            stopPillMotion()
            renderedPillFrame = .resting(
                at: targetX,
                sizeScale: configuration.sizeScale,
                shapeStyle: configuration.shapeStyle
            )
            renderArtwork()
            return
        }

        let sourceX = pillMotion == nil
            ? indicatorCenterX(for: previousIndex)
            : renderedPillFrame?.x ?? indicatorCenterX(for: previousIndex)
        let activeSize = configuration.shapeStyle.activeIndicatorSize(
            sizeScale: configuration.sizeScale
        )
        let motion = StatusPillMotion(
            fromX: sourceX,
            toX: targetX,
            initialWidth: renderedPillFrame?.width
                ?? activeSize.width,
            initialHeight: renderedPillFrame?.height
                ?? activeSize.height,
            startTime: CACurrentMediaTime(),
            sizeScale: configuration.sizeScale,
            itemWidth: renderedItemWidth,
            style: configuration.animationStyle,
            shapeStyle: configuration.shapeStyle
        )
        transitionSourceIndex = configuration.animationStyle
            .blendsIndicatorAppearanceDuringTransition
            ? previousIndex
            : nil
        pillMotion = motion
        renderedPillFrame = motion.frame(at: motion.startTime)
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
        guard let configuration else { return }
        let motion = StatusHoverMotion(
            index: index,
            fromScale: hoverScales[index]
                ?? CGSize(width: 1, height: 1),
            isHovered: isHovered,
            isActive: index == renderedActiveIndex,
            startTime: CACurrentMediaTime(),
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

        hoverMotions[index] = motion
        configureDisplayLinkIfNeeded()
        updateDisplayLinkState()
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

    private func renderArtwork() {
        renderer?.update(
            pill: renderedPillFrame,
            activeIndex: renderedActiveIndex,
            transitionSourceIndex: transitionSourceIndex,
            hoverScales: hoverScales,
            presentation: artworkPresentation
        )
        needsDisplay = true
    }

    private func stopPillMotion() {
        pillMotion = nil
        transitionSourceIndex = nil
        updateDisplayLinkState()
    }

    private func updateDisplayLinkState() {
        animationDisplayLink?.isPaused = pillMotion == nil
            && hoverMotions.isEmpty
            && artworkRefreshMotion == nil
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
        artworkPresentation = .identity
        artworkRefreshDidApplySettings = false
        stopAnimations()
        needsDisplay = true
    }
}
