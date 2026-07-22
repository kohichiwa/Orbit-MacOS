import AppKit

/// Owns the one image installed on `NSStatusBarButton`.
///
/// Animation redraws a tiny, persistent bitmap representation in place. The
/// image object, its pixels and the button hierarchy stay independent from
/// macOS menu bar appearance changes between Spaces.
nonisolated final class StatusIndicatorImageRenderer {
    let count: Int
    let imageSize: NSSize
    let image: NSImage

    private(set) var pill: StatusPillFrame?
    private(set) var activeIndex: Int?
    private(set) var transitionSourceIndex: Int?
    private(set) var hoverScales: [Int: CGSize] = [:]
    private(set) var presentation: StatusArtworkPresentation = .identity
    private let bitmap: NSBitmapImageRep
    private let indicatorKinds: [SpaceIndicatorKind]
    private let indicatorColors: [NSColor]
    private let showsThinOutline: Bool
    private let shapeStyle: IndicatorShapeStyle
    private let sizeScale: CGFloat
    private let itemWidth: CGFloat
    private let horizontalPadding: CGFloat
    private let horizontalOverflowPadding: CGFloat
    private let dotDiameter: CGFloat
    private let scale: CGFloat = 2

    init(
        count: Int,
        indicatorKinds: [SpaceIndicatorKind]? = nil,
        indicatorColors: [NSColor] = [.controlAccentColor],
        showsThinOutline: Bool = false,
        shapeStyle: IndicatorShapeStyle = .standard,
        sizeScale: CGFloat = 1,
        spacingScale: CGFloat = 1,
        imageHeight: CGFloat = StatusItemArtwork.imageHeight,
        horizontalOverflowPadding: CGFloat = 0
    ) {
        self.count = max(count, 1)
        self.showsThinOutline = showsThinOutline
        self.shapeStyle = shapeStyle
        self.sizeScale = sizeScale
        itemWidth = StatusItemArtwork.itemWidth(
            sizeScale: sizeScale,
            spacingScale: spacingScale
        )
        horizontalPadding = StatusItemArtwork.horizontalPadding(
            sizeScale: sizeScale
        )
        self.horizontalOverflowPadding = max(
            horizontalOverflowPadding,
            0
        )
        dotDiameter = StatusItemArtwork.dotDiameter(sizeScale: sizeScale)
        let normalizedKinds = indicatorKinds?.count == self.count
            ? indicatorKinds!
            : (0..<self.count).map { .desktop(colorIndex: $0) }
        let fixedColors = indicatorColors.isEmpty
            ? [Self.fixedSRGBColor(from: .controlAccentColor)]
            : indicatorColors.map(Self.fixedSRGBColor)
        self.indicatorKinds = normalizedKinds
        self.indicatorColors = normalizedKinds.map { kind in
            let colorIndex = kind.colorIndex
            return fixedColors.indices.contains(colorIndex)
                ? fixedColors[colorIndex]
                : fixedColors[0]
        }
        imageSize = NSSize(
            width: CGFloat(self.count) * itemWidth
                + self.horizontalOverflowPadding * 2,
            height: imageHeight
        )

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(imageSize.width * scale),
            pixelsHigh: Int(imageSize.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            preconditionFailure("Could not allocate status item artwork")
        }
        bitmap.size = imageSize
        self.bitmap = bitmap

        let image = NSImage(size: imageSize)
        image.addRepresentation(bitmap)
        image.cacheMode = .never
        image.isTemplate = false
        self.image = image

        redraw()
    }

    func update(
        pill: StatusPillFrame?,
        activeIndex: Int? = nil,
        transitionSourceIndex: Int? = nil,
        hoverScales: [Int: CGSize] = [:],
        presentation: StatusArtworkPresentation = .identity
    ) {
        self.pill = pill
        self.activeIndex = activeIndex.flatMap {
            (0..<count).contains($0) ? $0 : nil
        }
        self.transitionSourceIndex = transitionSourceIndex.flatMap {
            (0..<count).contains($0) ? $0 : nil
        }
        self.hoverScales = hoverScales.filter {
            (0..<count).contains($0.key)
                && $0.value.width > 0
                && $0.value.height > 0
        }
        self.presentation = presentation
        redraw()
    }

    private func redraw() {
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        let graphics = context.cgContext
        graphics.clear(
            CGRect(
                x: 0,
                y: 0,
                width: bitmap.pixelsWide,
                height: bitmap.pixelsHigh
            )
        )

        graphics.saveGState()
        defer { graphics.restoreGState() }
        graphics.setAlpha(min(max(presentation.opacity, 0), 1))
        let center = CGPoint(
            x: imageSize.width / 2,
            y: imageSize.height / 2
        )
        graphics.translateBy(x: center.x, y: center.y)
        graphics.scaleBy(
            x: max(presentation.scaleX, 0.001),
            y: max(presentation.scaleY, 0.001)
        )
        graphics.translateBy(x: -center.x, y: -center.y)

        // NSGraphicsContext already derives a 2x CTM from bitmap.size versus
        // pixelsWide/pixelsHigh. Scaling it again makes the artwork 4x and
        // clips the right-hand dots and pill at the image boundary.

        // Keep these pixels appearance-independent. A template image would be
        // re-tinted by AppKit while the menu bar itself crossfades between
        // Spaces, producing one mismatched frame during an active animation.
        let transition = transitionState(for: pill)
        let hiddenActiveIndex = transition == nil
            ? pill.flatMap { activeIndex ?? inferredIndex(for: $0) }
            : nil
        for index in 0..<count {
            guard index != hiddenActiveIndex else { continue }
            let center = NSPoint(
                x: horizontalOverflowPadding
                    + CGFloat(index) * itemWidth
                    + itemWidth / 2,
                y: imageSize.height / 2
            )
            let presentation = inactivePresentation(
                at: index,
                transition: transition
            )
            drawInactiveIndicator(
                at: center,
                index: index,
                opacity: presentation.opacity,
                transitionScale: presentation.scale
            )
        }

        guard let pill else { return }
        let pillIndex = activeIndex ?? inferredIndex(for: pill) ?? 0
        let hoverScale = pillHoverScale(
            for: pillIndex,
            pill: pill
        )
        let width = pill.width * hoverScale.width
        let height = pill.height * hoverScale.height
        let centerX = pill.x - horizontalPadding
            + horizontalOverflowPadding
        let rect = NSRect(
            x: centerX - width / 2,
            y: (imageSize.height - height) / 2,
            width: width,
            height: height
        )
        if let transition {
            drawTransitioningPill(
                in: rect,
                sourceIndex: transition.sourceIndex,
                targetIndex: transition.targetIndex,
                progress: transition.progress,
                waist: pill.waist
            )
        } else {
            drawActiveIndicator(
                in: rect,
                kind: indicatorKinds[pillIndex],
                color: indicatorColors[pillIndex]
            )
        }
    }

    private func drawInactiveIndicator(
        at center: NSPoint,
        index: Int,
        opacity: CGFloat = 1,
        transitionScale: CGFloat = 1
    ) {
        guard opacity > 0.001 else { return }
        let hoverScale = hoverScales[index]
            ?? CGSize(width: 1, height: 1)
        let width = dotDiameter * hoverScale.width * transitionScale
        let height = dotDiameter * hoverScale.height * transitionScale
        let rect = NSRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
        let color = indicatorColors[index]

        if indicatorKinds[index].isFullscreen {
            drawHollowIndicator(
                in: rect,
                color: color,
                strokeOpacity: 0.46 * opacity,
                thinOutlineOpacity: 0.25 * opacity,
                lineWidth: fullscreenOutlineWidth
            )
        } else {
            drawFilledIndicator(
                in: rect,
                color: color,
                fillOpacity: 0.32 * opacity,
                outlineOpacity: 0.25 * opacity
            )
        }
    }

    private func drawTransitioningPill(
        in rect: NSRect,
        sourceIndex: Int,
        targetIndex: Int,
        progress: CGFloat,
        waist: CGFloat
    ) {
        let visualProgress = smoothStep(
            remap(progress, from: 0.22, to: 0.82)
        )
        let sourceKind = indicatorKinds[sourceIndex]
        let targetKind = indicatorKinds[targetIndex]
        let color = interpolatedColor(
            from: indicatorColors[sourceIndex],
            to: indicatorColors[targetIndex],
            progress: visualProgress
        )

        if sourceKind.isFullscreen == targetKind.isFullscreen {
            drawActiveIndicator(
                in: rect,
                kind: targetKind,
                color: color,
                waist: waist
            )
            return
        }

        // A desktop fill and a full-screen inner outline dissolve through one
        // another while sharing the exact same liquid silhouette. This avoids
        // the one-frame visual switch that previously made mixed transitions
        // feel like a stutter.
        drawActiveIndicator(
            in: rect,
            kind: sourceKind,
            color: color,
            opacity: 1 - visualProgress,
            waist: waist
        )
        drawActiveIndicator(
            in: rect,
            kind: targetKind,
            color: color,
            opacity: visualProgress,
            waist: waist
        )
    }

    private func drawActiveIndicator(
        in rect: NSRect,
        kind: SpaceIndicatorKind,
        color: NSColor,
        opacity: CGFloat = 1,
        waist: CGFloat = 0
    ) {
        guard opacity > 0.001 else { return }
        if kind.isFullscreen {
            drawHollowIndicator(
                in: rect,
                color: color,
                strokeOpacity: opacity,
                thinOutlineOpacity: 0.25 * opacity,
                lineWidth: fullscreenOutlineWidth * 1.5,
                waist: waist
            )
        } else {
            drawFilledIndicator(
                in: rect,
                color: color,
                fillOpacity: opacity,
                outlineOpacity: 0.25 * opacity,
                waist: waist
            )
        }
    }

    private func drawHollowIndicator(
        in rect: NSRect,
        color: NSColor,
        strokeOpacity: CGFloat,
        thinOutlineOpacity: CGFloat,
        lineWidth: CGFloat,
        waist: CGFloat = 0
    ) {
        if showsThinOutline {
            let outlineWidth = thinOutlineWidth
            drawOutline(
                in: rect,
                color: thinOutlineColor(
                    for: color,
                    opacity: thinOutlineOpacity
                ),
                lineWidth: lineWidth + outlineWidth * 2,
                waist: waist
            )
            drawOutline(
                in: rect.insetBy(
                    dx: outlineWidth,
                    dy: outlineWidth
                ),
                color: color.withAlphaComponent(strokeOpacity),
                lineWidth: lineWidth,
                waist: waist
            )
            return
        }
        drawOutline(
            in: rect,
            color: color.withAlphaComponent(strokeOpacity),
            lineWidth: lineWidth,
            waist: waist
        )
    }

    private func drawFilledIndicator(
        in rect: NSRect,
        color: NSColor,
        fillOpacity: CGFloat,
        outlineOpacity: CGFloat,
        waist: CGFloat = 0
    ) {
        color.withAlphaComponent(fillOpacity).setFill()
        indicatorPath(in: rect, waist: waist).fill()

        guard showsThinOutline else { return }
        drawOutline(
            in: rect,
            color: thinOutlineColor(
                for: color,
                opacity: outlineOpacity
            ),
            lineWidth: thinOutlineWidth,
            waist: waist
        )
    }

    private func thinOutlineColor(
        for color: NSColor,
        opacity: CGFloat
    ) -> NSColor {
        let color = Self.fixedSRGBColor(from: color)
        let luminance = 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
        return NSColor(
            white: luminance > 0.58 ? 0 : 1,
            alpha: opacity
        )
    }

    private func transitionState(
        for pill: StatusPillFrame?
    ) -> (sourceIndex: Int, targetIndex: Int, progress: CGFloat)? {
        guard
            let pill,
            !pill.isComplete,
            let sourceIndex = transitionSourceIndex,
            let targetIndex = activeIndex,
            sourceIndex != targetIndex
        else { return nil }
        return (sourceIndex, targetIndex, min(max(pill.progress, 0), 1))
    }

    /// The hovered target is still represented by its dot while the pill is
    /// travelling. Let the pill adopt hover only near arrival; multiplying a
    /// moving pill by the dot's relative scale produces clipped frames and a
    /// motion profile that differs from the status item.
    private func pillHoverScale(
        for index: Int,
        pill: StatusPillFrame
    ) -> CGSize {
        let target = hoverScales[index]
            ?? CGSize(width: 1, height: 1)
        guard !pill.isComplete else { return target }
        let adoption = smoothStep(
            remap(pill.progress, from: 0.58, to: 0.92)
        )
        return CGSize(
            width: 1 + (target.width - 1) * adoption,
            height: 1 + (target.height - 1) * adoption
        )
    }

    private func inactivePresentation(
        at index: Int,
        transition: (sourceIndex: Int, targetIndex: Int, progress: CGFloat)?
    ) -> (opacity: CGFloat, scale: CGFloat) {
        guard let transition else { return (1, 1) }

        if index == transition.sourceIndex {
            let reveal = smoothStep(
                remap(transition.progress, from: 0.18, to: 0.44)
            )
            return (reveal, 0.58 + 0.42 * reveal)
        }
        if index == transition.targetIndex {
            let absorption = smoothStep(
                remap(transition.progress, from: 0.54, to: 0.84)
            )
            return (1 - absorption, 1 - 0.42 * absorption)
        }
        return (1, 1)
    }

    private func interpolatedColor(
        from source: NSColor,
        to target: NSColor,
        progress: CGFloat
    ) -> NSColor {
        let source = Self.fixedSRGBColor(from: source)
        let target = Self.fixedSRGBColor(from: target)
        return NSColor(
            srgbRed: source.redComponent
                + (target.redComponent - source.redComponent) * progress,
            green: source.greenComponent
                + (target.greenComponent - source.greenComponent) * progress,
            blue: source.blueComponent
                + (target.blueComponent - source.blueComponent) * progress,
            alpha: 1
        )
    }

    private func remap(
        _ value: CGFloat,
        from start: CGFloat,
        to end: CGFloat
    ) -> CGFloat {
        min(max((value - start) / (end - start), 0), 1)
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func drawOutline(
        in rect: NSRect,
        color: NSColor,
        lineWidth: CGFloat,
        waist: CGFloat = 0
    ) {
        let inset = lineWidth / 2
        let innerRect = rect.insetBy(dx: inset, dy: inset)
        guard innerRect.width > 0, innerRect.height > 0 else { return }
        let path = indicatorPath(in: innerRect, waist: waist)
        path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    /// A subtly pinched liquid bridge. Its end caps retain the selected
    /// indicator shape while two mirrored cubic curves pull the long edges
    /// towards the centre. At zero waist this is the regular indicator path.
    private func indicatorPath(
        in rect: NSRect,
        waist: CGFloat
    ) -> NSBezierPath {
        let amount = min(max(waist, 0), 1)
        let radius = min(
            cornerRadius(for: rect),
            min(rect.width, rect.height) / 2
        )
        guard
            amount > 0.001,
            rect.width > rect.height * 1.6,
            radius > 0
        else {
            return NSBezierPath(
                roundedRect: rect,
                xRadius: radius,
                yRadius: radius
            )
        }

        let curve: CGFloat = 0.552_284_75
        let centreX = rect.midX
        let waistDepth = min(
            rect.height * 0.19 * amount,
            rect.height / 2 - 0.5
        )
        let shoulderReach = max(
            (rect.width / 2 - radius) * 0.58,
            0
        )
        let leftShoulderControl = centreX - shoulderReach
        let rightShoulderControl = centreX + shoulderReach
        let neckControl = min(rect.width * 0.12, rect.height * 0.8)

        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
        path.curve(
            to: NSPoint(x: centreX, y: rect.maxY - waistDepth),
            controlPoint1: NSPoint(x: leftShoulderControl, y: rect.maxY),
            controlPoint2: NSPoint(
                x: centreX - neckControl,
                y: rect.maxY - waistDepth
            )
        )
        path.curve(
            to: NSPoint(x: rect.maxX - radius, y: rect.maxY),
            controlPoint1: NSPoint(
                x: centreX + neckControl,
                y: rect.maxY - waistDepth
            ),
            controlPoint2: NSPoint(x: rightShoulderControl, y: rect.maxY)
        )
        path.curve(
            to: NSPoint(x: rect.maxX, y: rect.maxY - radius),
            controlPoint1: NSPoint(
                x: rect.maxX - radius + curve * radius,
                y: rect.maxY
            ),
            controlPoint2: NSPoint(
                x: rect.maxX,
                y: rect.maxY - radius + curve * radius
            )
        )
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + radius))
        path.curve(
            to: NSPoint(x: rect.maxX - radius, y: rect.minY),
            controlPoint1: NSPoint(
                x: rect.maxX,
                y: rect.minY + radius - curve * radius
            ),
            controlPoint2: NSPoint(
                x: rect.maxX - radius + curve * radius,
                y: rect.minY
            )
        )
        path.curve(
            to: NSPoint(x: centreX, y: rect.minY + waistDepth),
            controlPoint1: NSPoint(x: rightShoulderControl, y: rect.minY),
            controlPoint2: NSPoint(
                x: centreX + neckControl,
                y: rect.minY + waistDepth
            )
        )
        path.curve(
            to: NSPoint(x: rect.minX + radius, y: rect.minY),
            controlPoint1: NSPoint(
                x: centreX - neckControl,
                y: rect.minY + waistDepth
            ),
            controlPoint2: NSPoint(x: leftShoulderControl, y: rect.minY)
        )
        path.curve(
            to: NSPoint(x: rect.minX, y: rect.minY + radius),
            controlPoint1: NSPoint(
                x: rect.minX + radius - curve * radius,
                y: rect.minY
            ),
            controlPoint2: NSPoint(
                x: rect.minX,
                y: rect.minY + radius - curve * radius
            )
        )
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY - radius))
        path.curve(
            to: NSPoint(x: rect.minX + radius, y: rect.maxY),
            controlPoint1: NSPoint(
                x: rect.minX,
                y: rect.maxY - radius + curve * radius
            ),
            controlPoint2: NSPoint(
                x: rect.minX + radius - curve * radius,
                y: rect.maxY
            )
        )
        path.close()
        return path
    }

    private func cornerRadius(for rect: NSRect) -> CGFloat {
        switch shapeStyle {
        case .standard, .circles:
            rect.height / 2
        case .roundedRectangles:
            rect.height * 0.28
        }
    }

    private func inferredIndex(for pill: StatusPillFrame) -> Int? {
        let localCenter = pill.x - horizontalPadding
        let rawIndex = (
            localCenter - itemWidth / 2
        ) / itemWidth
        let index = Int(rawIndex.rounded())
        return (0..<count).contains(index) ? index : nil
    }

    private static func fixedSRGBColor(from color: NSColor) -> NSColor {
        guard
            let converted = color.usingColorSpace(.sRGB),
            let components = converted.cgColor.components,
            components.count >= 3
        else {
            return NSColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1)
        }

        return NSColor(
            srgbRed: components[0],
            green: components[1],
            blue: components[2],
            alpha: 1
        )
    }

    private var fullscreenOutlineWidth: CGFloat {
        max(1.1 * sizeScale, 1)
    }

    private var thinOutlineWidth: CGFloat {
        max(0.35 * sizeScale, 0.35)
    }
}
