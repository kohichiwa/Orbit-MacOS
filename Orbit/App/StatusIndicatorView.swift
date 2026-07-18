import AppKit
import QuartzCore

/// The complete status indicator rendered as one stable layer tree.
/// Each dot morphs itself into a pill on hover; no extra highlight is drawn.
@MainActor
final class StatusIndicatorView: NSView {
    let count: Int
    let sizeScale: CGFloat
    let spacingScale: CGFloat

    private let dotLayers: [CAShapeLayer]
    private let indicatorKinds: [SpaceIndicatorKind]
    private let indicatorColors: [NSColor]
    private let activePillLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    private(set) var hoveredIndex: Int?
    private(set) var activeIndex: Int?

    init(
        count: Int,
        sizeScale: CGFloat = 1,
        spacingScale: CGFloat = 1,
        indicatorKinds: [SpaceIndicatorKind]? = nil,
        indicatorColors: [NSColor] = [.controlAccentColor]
    ) {
        let normalizedCount = max(count, 1)
        let normalizedKinds = indicatorKinds?.count == normalizedCount
            ? indicatorKinds!
            : (0..<normalizedCount).map { .desktop(colorIndex: $0) }
        let fixedDesktopColors = indicatorColors.map(Self.fixedSRGBColor)

        self.count = normalizedCount
        self.sizeScale = sizeScale
        self.spacingScale = spacingScale
        self.indicatorKinds = normalizedKinds
        self.indicatorColors = normalizedKinds.map { kind in
            let colorIndex = kind.colorIndex
            return fixedDesktopColors.indices.contains(colorIndex)
                ? fixedDesktopColors[colorIndex]
                : Self.fixedSRGBColor(from: .controlAccentColor)
        }
        dotLayers = (0..<normalizedCount).map { _ in CAShapeLayer() }
        super.init(frame: .zero)

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layerContentsRedrawPolicy = .never

        for (index, dotLayer) in dotLayers.enumerated() {
            if isFullscreen(at: index) {
                dotLayer.fillColor = NSColor.clear.cgColor
                dotLayer.strokeColor = self.indicatorColors[index]
                    .withAlphaComponent(Self.inactiveIndicatorAlpha)
                    .cgColor
                dotLayer.lineWidth = fullscreenOutlineWidth
                dotLayer.lineJoin = .round
                setShape(
                    of: dotLayer,
                    size: dotSize,
                    strokeInset: fullscreenOutlineWidth / 2
                )
            } else {
                dotLayer.fillColor = self.indicatorColors[index]
                    .withAlphaComponent(Self.inactiveDesktopIndicatorAlpha)
                    .cgColor
                dotLayer.strokeColor = NSColor.clear.cgColor
                dotLayer.lineWidth = 0
                setShape(of: dotLayer, size: dotSize)
            }
            layer?.addSublayer(dotLayer)
        }

        activePillLayer.fillColor = self.indicatorColors[0].cgColor
        activePillLayer.strokeColor = NSColor.clear.cgColor
        activePillLayer.lineWidth = 0
        setShape(of: activePillLayer, size: activeSize)
        activePillLayer.opacity = 0
        layer?.addSublayer(activePillLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, dotLayer) in dotLayers.enumerated() {
            dotLayer.position = position(for: index)
        }
        if let activeIndex {
            activePillLayer.position = position(for: activeIndex)
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for dotLayer in dotLayers {
            dotLayer.contentsScale = scale
        }
        activePillLayer.contentsScale = scale
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredIndex(nil, animated: true)
    }

    func index(at point: CGPoint) -> Int? {
        let contentWidth = CGFloat(count) * itemWidth
        let relativeX = point.x - (bounds.width - contentWidth) / 2
        guard
            bounds.contains(point),
            relativeX >= 0,
            relativeX < contentWidth
        else { return nil }
        return Int(relativeX / itemWidth)
    }

    func setActiveIndex(_ index: Int?, animated: Bool) {
        let previousIndex = activeIndex
        activeIndex = index.flatMap { (0..<count).contains($0) ? $0 : nil }

        guard let activeIndex else {
            activePillLayer.removeAllAnimations()
            setOpacity(0, on: activePillLayer)
            refreshDotVisibility()
            return
        }

        let destination = position(for: activeIndex)
        let origin = activePillLayer.presentation()?.position
            ?? previousIndex.map { position(for: $0) }
            ?? destination
        let originSize = activePillLayer.presentation()?.bounds.size
            ?? activePillLayer.bounds.size
        let originPath = activePillLayer.presentation()?.path
            ?? activePillLayer.path
            ?? shapePath(for: originSize)
        let originColor = activePillLayer.presentation()?.fillColor
            ?? activePillLayer.fillColor
        let originStrokeColor = activePillLayer.presentation()?.strokeColor
            ?? activePillLayer.strokeColor
        let originLineWidth = activePillLayer.presentation()?.lineWidth
            ?? activePillLayer.lineWidth
        let fullscreen = isFullscreen(at: activeIndex)
        let destinationColor = fullscreen
            ? indicatorColors[activeIndex].withAlphaComponent(0).cgColor
            : indicatorColors[activeIndex].cgColor
        let destinationStrokeColor = fullscreen
            ? indicatorColors[activeIndex].cgColor
            : NSColor.clear.cgColor
        let destinationLineWidth = fullscreen
            ? fullscreenActiveOutlineWidth
            : 0
        let destinationStrokeInset = destinationLineWidth / 2

        activePillLayer.removeAnimation(forKey: "activeMove")
        if previousIndex != activeIndex {
            activePillLayer.removeAnimation(forKey: "activeHover")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if previousIndex != activeIndex {
            activePillLayer.setAffineTransform(.identity)
        }
        activePillLayer.position = destination
        activePillLayer.opacity = 1
        activePillLayer.bounds = CGRect(origin: .zero, size: activeSize)
        activePillLayer.path = shapePath(
            for: activeSize,
            strokeInset: destinationStrokeInset
        )
        activePillLayer.fillColor = destinationColor
        activePillLayer.strokeColor = destinationStrokeColor
        activePillLayer.lineWidth = destinationLineWidth
        CATransaction.commit()
        refreshDotVisibility()

        guard
            animated,
            previousIndex != nil,
            previousIndex != activeIndex,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else { return }

        let crossedSpaces = max(
            abs(destination.x - origin.x) / itemWidth,
            1
        )
        let stretchedSize = CGSize(
            width: scaled(17.6)
                + min(crossedSpaces - 1, 4) * scaled(0.45),
            height: scaled(6)
        )
        let reboundSize = CGSize(
            width: scaled(11.3),
            height: scaled(7.45)
        )
        let keyTimes: [NSNumber] = [0, 0.34, 0.72, 1]

        let positionAnimation = CABasicAnimation(keyPath: "position")
        positionAnimation.fromValue = origin
        positionAnimation.toValue = destination
        positionAnimation.timingFunction = CAMediaTimingFunction(
            controlPoints: 0.20,
            0.70,
            0.24,
            1
        )

        let width = CAKeyframeAnimation(keyPath: "bounds.size.width")
        width.values = [originSize.width, stretchedSize.width, reboundSize.width, activeSize.width]
        width.keyTimes = keyTimes
        width.timingFunctions = liquidTimingFunctions

        let height = CAKeyframeAnimation(keyPath: "bounds.size.height")
        height.values = [originSize.height, stretchedSize.height, reboundSize.height, activeSize.height]
        height.keyTimes = keyTimes
        height.timingFunctions = liquidTimingFunctions

        let path = CAKeyframeAnimation(keyPath: "path")
        path.values = [
            originPath,
            shapePath(for: stretchedSize, strokeInset: destinationStrokeInset),
            shapePath(for: reboundSize, strokeInset: destinationStrokeInset),
            shapePath(for: activeSize, strokeInset: destinationStrokeInset)
        ]
        path.keyTimes = keyTimes
        path.timingFunctions = liquidTimingFunctions

        let color = CABasicAnimation(keyPath: "fillColor")
        color.fromValue = originColor
        color.toValue = destinationColor
        color.timingFunction = CAMediaTimingFunction(
            controlPoints: 0.20,
            0.70,
            0.24,
            1
        )

        let strokeColor = CABasicAnimation(keyPath: "strokeColor")
        strokeColor.fromValue = originStrokeColor
        strokeColor.toValue = destinationStrokeColor
        strokeColor.timingFunction = color.timingFunction

        let lineWidth = CABasicAnimation(keyPath: "lineWidth")
        lineWidth.fromValue = originLineWidth
        lineWidth.toValue = destinationLineWidth
        lineWidth.timingFunction = color.timingFunction

        let liquidMove = CAAnimationGroup()
        liquidMove.animations = [
            positionAnimation,
            width,
            height,
            path,
            color,
            strokeColor,
            lineWidth
        ]
        liquidMove.duration = 0.27
            + min(TimeInterval(crossedSpaces - 1) * 0.01, 0.03)
        activePillLayer.add(liquidMove, forKey: "activeMove")
    }

    func animateRemoval(
        at removedIndex: Int,
        resultingCount: Int,
        fullscreen: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        guard
            dotLayers.indices.contains(removedIndex),
            resultingCount == count - 1,
            resultingCount > 0,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else {
            completion()
            return
        }

        activePillLayer.removeAnimation(forKey: "activeMove")
        let duration: CFTimeInterval = fullscreen ? 0.38 : 0.34
        let timing = CAMediaTimingFunction(controlPoints: 0.20, 0.68, 0.24, 1)
        let removedLayer: CAShapeLayer = activeIndex == removedIndex
            ? activePillLayer
            : dotLayers[removedIndex]
        let disappearingLayer = removalCopy(of: removedLayer)
        let originTransform = disappearingLayer.transform
        let destinationTransform = CATransform3DScale(
            originTransform,
            0.18,
            0.18,
            1
        )
        let originOpacity = disappearingLayer.opacity

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.addSublayer(disappearingLayer)
        removedLayer.opacity = 0
        disappearingLayer.opacity = 0
        disappearingLayer.transform = destinationTransform
        if fullscreen {
            disappearingLayer.strokeEnd = 0
        }
        CATransaction.commit()

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = originOpacity
        opacity.toValue = 0
        opacity.timingFunction = timing

        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = originTransform
        transform.toValue = destinationTransform
        transform.timingFunction = timing

        var removalAnimations: [CAAnimation] = [opacity, transform]
        if fullscreen {
            let stroke = CABasicAnimation(keyPath: "strokeEnd")
            stroke.fromValue = 1
            stroke.toValue = 0
            stroke.timingFunction = timing
            removalAnimations.append(stroke)
        }
        let removal = CAAnimationGroup()
        removal.animations = removalAnimations
        removal.duration = duration
        removal.fillMode = .both
        removal.isRemovedOnCompletion = false
        disappearingLayer.add(removal, forKey: "structuralRemoval")

        for (oldIndex, layer) in dotLayers.enumerated()
        where oldIndex != removedIndex {
            let newIndex = oldIndex > removedIndex ? oldIndex - 1 : oldIndex
            animatePosition(
                of: layer,
                to: position(for: newIndex, itemCount: resultingCount),
                duration: duration,
                timing: timing
            )
        }

        if let activeIndex, activeIndex != removedIndex {
            let newActiveIndex = activeIndex > removedIndex
                ? activeIndex - 1
                : activeIndex
            animatePosition(
                of: activePillLayer,
                to: position(for: newActiveIndex, itemCount: resultingCount),
                duration: duration,
                timing: timing
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            disappearingLayer.removeFromSuperlayer()
            completion()
        }
    }

    private func removalCopy(of sourceLayer: CAShapeLayer) -> CAShapeLayer {
        let visibleLayer = sourceLayer.presentation() ?? sourceLayer
        let copy = CAShapeLayer()
        copy.anchorPoint = visibleLayer.anchorPoint
        copy.bounds = visibleLayer.bounds
        copy.position = visibleLayer.position
        copy.transform = visibleLayer.transform
        copy.opacity = visibleLayer.opacity
        copy.path = visibleLayer.path
        copy.fillColor = visibleLayer.fillColor
        copy.strokeColor = visibleLayer.strokeColor
        copy.lineWidth = visibleLayer.lineWidth
        copy.lineCap = visibleLayer.lineCap
        copy.lineJoin = visibleLayer.lineJoin
        copy.strokeStart = visibleLayer.strokeStart
        copy.strokeEnd = visibleLayer.strokeEnd
        copy.contentsScale = visibleLayer.contentsScale
        return copy
    }

    func setHoveredIndex(_ index: Int?, animated: Bool) {
        let normalizedIndex = index.flatMap { (0..<count).contains($0) ? $0 : nil }
        guard normalizedIndex != hoveredIndex else { return }
        let previousIndex = hoveredIndex
        hoveredIndex = normalizedIndex

        if let previousIndex {
            if previousIndex == activeIndex {
                animateActivePill(isHovered: false, animated: animated)
            } else {
                morphDot(at: previousIndex, hovered: false, animated: animated)
            }
        }

        if let normalizedIndex {
            if normalizedIndex == activeIndex {
                animateActivePill(isHovered: true, animated: animated)
            } else {
                morphDot(at: normalizedIndex, hovered: true, animated: animated)
            }
        }
    }

    private var dotSize: CGSize {
        CGSize(
            width: scaled(4.5),
            height: scaled(4.5)
        )
    }

    private var hoveredDotSize: CGSize {
        CGSize(
            width: scaled(11.75),
            height: scaled(7.75)
        )
    }

    private var activeSize: CGSize {
        CGSize(
            width: scaled(12),
            height: scaled(7)
        )
    }

    private var hoveredFullscreenSize: CGSize {
        hoveredDotSize
    }

    private var fullscreenOutlineWidth: CGFloat {
        max(scaled(1.1), 1)
    }

    private var fullscreenActiveOutlineWidth: CGFloat {
        fullscreenOutlineWidth * 1.5
    }

    private var itemWidth: CGFloat {
        StatusItemArtwork.itemWidth(
            sizeScale: sizeScale,
            spacingScale: spacingScale
        )
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        StatusItemArtwork.scaled(value, sizeScale: sizeScale)
    }

    private func updateHover(at point: CGPoint) {
        setHoveredIndex(index(at: point), animated: true)
    }

    private func position(for index: Int) -> CGPoint {
        position(for: index, itemCount: count)
    }

    private func position(for index: Int, itemCount: Int) -> CGPoint {
        let contentWidth = CGFloat(itemCount) * itemWidth
        return CGPoint(
            x: (bounds.width - contentWidth) / 2
                + CGFloat(index) * itemWidth
                + itemWidth / 2,
            y: bounds.midY
        )
    }

    private func animatePosition(
        of target: CALayer,
        to destination: CGPoint,
        duration: CFTimeInterval,
        timing: CAMediaTimingFunction
    ) {
        let origin = target.presentation()?.position ?? target.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        target.position = destination
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = origin
        animation.toValue = destination
        animation.duration = duration
        animation.timingFunction = timing
        target.add(animation, forKey: "structuralPosition")
    }

    private func refreshDotVisibility() {
        for (index, dotLayer) in dotLayers.enumerated() {
            let hiddenByActivePill = index == activeIndex
            setOpacity(hiddenByActivePill ? 0 : 1, on: dotLayer)
        }
    }

    private func morphDot(at index: Int, hovered: Bool, animated: Bool) {
        let dotLayer = dotLayers[index]
        let fullscreen = isFullscreen(at: index)
        let destination = fullscreen
            ? (hovered ? hoveredFullscreenSize : dotSize)
            : (hovered ? hoveredDotSize : dotSize)
        let strokeInset = fullscreen
            ? fullscreenOutlineWidth / 2
            : 0
        let origin = dotLayer.presentation()?.bounds.size ?? dotLayer.bounds.size
        let originPath = dotLayer.presentation()?.path
            ?? dotLayer.path
            ?? shapePath(for: origin, strokeInset: strokeInset)
        dotLayer.removeAnimation(forKey: "liquidMorph")
        setShape(of: dotLayer, size: destination, strokeInset: strokeInset)

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }

        let width = CAKeyframeAnimation(keyPath: "bounds.size.width")
        let overshoot = hovered
            ? destination.width + scaled(1.1)
            : destination.width - scaled(0.15)
        width.values = [origin.width, overshoot, destination.width]
        width.keyTimes = hovered ? [0, 0.68, 1] : [0, 0.86, 1]
        width.timingFunctions = hovered ? hoverTimingFunctions : hoverExitTimingFunctions

        let height = CAKeyframeAnimation(keyPath: "bounds.size.height")
        let verticalBounce = hovered
            ? destination.height - scaled(0.4)
            : destination.height + scaled(0.15)
        height.values = [origin.height, verticalBounce, destination.height]
        height.keyTimes = width.keyTimes
        height.timingFunctions = width.timingFunctions

        let path = CAKeyframeAnimation(keyPath: "path")
        path.values = [
            originPath,
            shapePath(
                for: CGSize(width: overshoot, height: verticalBounce),
                strokeInset: strokeInset
            ),
            shapePath(for: destination, strokeInset: strokeInset)
        ]
        path.keyTimes = width.keyTimes
        path.timingFunctions = width.timingFunctions

        let group = CAAnimationGroup()
        group.animations = [width, height, path]
        group.duration = hovered ? 0.22 : 0.30
        dotLayer.add(group, forKey: "liquidMorph")
    }

    private func animateActivePill(isHovered: Bool, animated: Bool) {
        let origin = activePillLayer.presentation()?.transform ?? activePillLayer.transform
        activePillLayer.removeAnimation(forKey: "activeHover")
        let scaleX: CGFloat = isHovered ? 1.38 : 1
        let scaleY: CGFloat = isHovered ? 1.25 : 1

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        activePillLayer.setAffineTransform(
            CGAffineTransform(scaleX: scaleX, y: scaleY)
        )
        CATransaction.commit()

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }

        let animation = CASpringAnimation(keyPath: "transform")
        animation.fromValue = origin
        animation.toValue = CATransform3DMakeAffineTransform(
            CGAffineTransform(scaleX: scaleX, y: scaleY)
        )
        animation.mass = 0.7
        animation.stiffness = 340
        animation.damping = 30
        animation.initialVelocity = 0
        animation.duration = animation.settlingDuration
        activePillLayer.add(animation, forKey: "activeHover")
    }

    private var hoverTimingFunctions: [CAMediaTimingFunction] {
        [
            CAMediaTimingFunction(controlPoints: 0.16, 0.82, 0.24, 1),
            CAMediaTimingFunction(controlPoints: 0.22, 0.62, 0.32, 1)
        ]
    }

    private var hoverExitTimingFunctions: [CAMediaTimingFunction] {
        [
            CAMediaTimingFunction(controlPoints: 0.42, 0, 0.20, 1),
            CAMediaTimingFunction(controlPoints: 0.20, 0.72, 0.24, 1)
        ]
    }

    private var liquidTimingFunctions: [CAMediaTimingFunction] {
        [
            CAMediaTimingFunction(controlPoints: 0.18, 0.74, 0.22, 1),
            CAMediaTimingFunction(controlPoints: 0.28, 0, 0.35, 1),
            CAMediaTimingFunction(controlPoints: 0.20, 0.78, 0.28, 1)
        ]
    }

    private func setShape(
        of shapeLayer: CAShapeLayer,
        size: CGSize,
        strokeInset: CGFloat = 0
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.bounds = CGRect(origin: .zero, size: size)
        shapeLayer.path = shapePath(for: size, strokeInset: strokeInset)
        CATransaction.commit()
    }

    private func shapePath(
        for size: CGSize,
        strokeInset: CGFloat = 0
    ) -> CGPath {
        let rect = CGRect(origin: .zero, size: size).insetBy(
            dx: strokeInset,
            dy: strokeInset
        )
        return CGPath(
            roundedRect: rect,
            cornerWidth: rect.height / 2,
            cornerHeight: rect.height / 2,
            transform: nil
        )
    }

    private func isFullscreen(at index: Int) -> Bool {
        guard indicatorKinds.indices.contains(index) else { return false }
        return indicatorKinds[index].isFullscreen
    }

    private func setOpacity(_ opacity: Float, on target: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        target.opacity = opacity
        CATransaction.commit()
    }

    private static func fixedSRGBColor(from color: NSColor) -> NSColor {
        guard let converted = color.usingColorSpace(.sRGB) else {
            return NSColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1)
        }
        return NSColor(
            srgbRed: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: 1
        )
    }

    private static let inactiveIndicatorAlpha: CGFloat = 0.46
    private static let inactiveDesktopIndicatorAlpha: CGFloat = 0.55
}
