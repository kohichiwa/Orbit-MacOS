import AppKit

nonisolated struct StatusResolvedPillAppearance {
    let color: NSColor
    let desktopOpacity: CGFloat
    let fullscreenOpacity: CGFloat
}

nonisolated struct StatusInactiveIndicatorAppearance {
    let opacity: CGFloat
    let scale: CGFloat
}

/// A value snapshot of the pixels whose meaning changes during a Space
/// transition. Geometry is sampled separately by `StatusPillMotion`; this
/// snapshot lets an interrupted transition preserve color, fill/outline mix
/// and dot visibility even when its new destination is a third Space.
nonisolated struct StatusInterruptedTransitionPresentation {
    let pill: StatusResolvedPillAppearance
    let inactiveIndicators: [StatusInactiveIndicatorAppearance]
    let applicationPreviewBaseSize: NSSize?
}

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
    private(set) var interruptedTransitionPresentation:
        StatusInterruptedTransitionPresentation?
    private(set) var hoverScales: [Int: CGSize] = [:]
    private(set) var presentation: StatusArtworkPresentation = .identity
    private(set) var applicationPreviewFrame =
        StatusApplicationPreviewFrame.hidden
    private(set) var applicationPreviewTracksPill = false
    private(set) var currentApplicationPreviewExtraWidth: CGFloat = 0
    private(set) var currentContentScale: CGFloat = 1
    private(set) var currentStatusItemWidth: CGFloat = 0
    private var currentApplicationPreviewHitRange: ClosedRange<CGFloat>?
    let applicationPreviewMaximumExtraWidth: CGFloat
    private let bitmap: NSBitmapImageRep
    private let indicatorKinds: [SpaceIndicatorKind]
    private var indicatorColors: [NSColor]
    private let increasedContrast: Bool
    private let shapeStyle: IndicatorShapeStyle
    private let sizeScale: CGFloat
    private let itemWidth: CGFloat
    private let edgeItemWidth: CGFloat
    private let horizontalPadding: CGFloat
    private let horizontalOverflowPadding: CGFloat
    private let dotDiameter: CGFloat
    private let baseContentWidth: CGFloat
    private let baseStatusItemWidth: CGFloat
    private let maximumVisibleContentWidth: CGFloat?
    private var applicationPreviewIndex: Int?
    private var applicationIcons: [NSImage]
    private let maximumApplicationPreviewIconCount: Int
    private let applicationPreviewScale: CGFloat
    private let applicationIconSize: CGFloat
    private let scale: CGFloat = 2

    init(
        count: Int,
        indicatorKinds: [SpaceIndicatorKind]? = nil,
        indicatorColors: [NSColor] = [.controlAccentColor],
        shapeStyle: IndicatorShapeStyle = .standard,
        sizeScale: CGFloat = 1,
        spacingScale: CGFloat = 1,
        imageHeight: CGFloat = StatusItemArtwork.imageHeight,
        horizontalOverflowPadding: CGFloat = 0,
        increasedContrast: Bool = false,
        applicationPreviewIndex: Int? = nil,
        applicationIcons: [NSImage] = [],
        maximumApplicationPreviewIconCount: Int = 0,
        maximumVisibleContentWidth: CGFloat? = nil
    ) {
        let normalizedCount = max(count, 1)
        self.count = normalizedCount
        self.increasedContrast = increasedContrast
        self.shapeStyle = shapeStyle
        self.sizeScale = sizeScale
        itemWidth = StatusItemArtwork.itemWidth(
            sizeScale: sizeScale,
            spacingScale: spacingScale
        )
        edgeItemWidth = StatusItemArtwork.edgeItemWidth(sizeScale: sizeScale)
        horizontalPadding = StatusItemArtwork.horizontalPadding(
            sizeScale: sizeScale
        )
        self.horizontalOverflowPadding = max(
            horizontalOverflowPadding,
            0
        )
        dotDiameter = StatusItemArtwork.dotDiameter(sizeScale: sizeScale)
        applicationPreviewScale = min(
            max(sizeScale, 0.01),
            max(
                imageHeight / StatusApplicationPreviewLayout.pillHeight,
                0.01
            )
        )
        applicationIconSize =
            StatusApplicationPreviewLayout.iconSize
            * applicationPreviewScale
        let previewIconCapacity = max(
            maximumApplicationPreviewIconCount,
            applicationIcons.count
        )
        self.maximumApplicationPreviewIconCount = previewIconCapacity
        let normalizedIcons = Array(
            applicationIcons.prefix(previewIconCapacity)
        )
        let normalizedPreviewIndex = applicationPreviewIndex.flatMap {
            (0..<normalizedCount).contains($0) && !normalizedIcons.isEmpty
                ? $0
                : nil
        }
        self.applicationPreviewIndex = normalizedPreviewIndex
        self.applicationIcons = normalizedPreviewIndex == nil
            ? []
            : normalizedIcons
        let baseContentWidth = StatusItemArtwork.contentWidth(
            for: normalizedCount,
            sizeScale: sizeScale,
            spacingScale: spacingScale
        )
        self.baseContentWidth = baseContentWidth
        baseStatusItemWidth = StatusItemArtwork.preferredWidth(
            for: normalizedCount,
            sizeScale: sizeScale,
            spacingScale: spacingScale
        )
        self.maximumVisibleContentWidth = maximumVisibleContentWidth.map {
            max($0, 0.01)
        }
        let unconstrainedPreviewExtraWidth =
            Self.applicationPreviewMaximumExtraWidth(
                sizeScale: sizeScale,
                iconCount: previewIconCapacity
            )
        if let maximumVisibleContentWidth = self.maximumVisibleContentWidth {
            applicationPreviewMaximumExtraWidth = min(
                unconstrainedPreviewExtraWidth,
                max(
                    maximumVisibleContentWidth - baseStatusItemWidth,
                    0
                )
            )
        } else {
            applicationPreviewMaximumExtraWidth =
                unconstrainedPreviewExtraWidth
        }
        let normalizedKinds = indicatorKinds?.count == normalizedCount
            ? indicatorKinds!
            : (0..<normalizedCount).map { .desktop(colorIndex: $0) }
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
            width: baseContentWidth
                + applicationPreviewMaximumExtraWidth
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

        currentStatusItemWidth = baseStatusItemWidth
        redraw()
    }

    func setApplicationPreview(
        index: Int?,
        icons: [NSImage]
    ) {
        let normalizedIcons = Array(
            icons.prefix(maximumApplicationPreviewIconCount)
        )
        applicationPreviewIndex = index.flatMap {
            (0..<count).contains($0) && !normalizedIcons.isEmpty
                ? $0
                : nil
        }
        applicationIcons = applicationPreviewIndex == nil
            ? []
            : normalizedIcons
    }

    func setIndicatorColors(_ colors: [NSColor]) {
        let fixedColors = colors.isEmpty
            ? [Self.fixedSRGBColor(from: .controlAccentColor)]
            : colors.map(Self.fixedSRGBColor)
        indicatorColors = indicatorKinds.map { kind in
            let colorIndex = kind.colorIndex
            return fixedColors.indices.contains(colorIndex)
                ? fixedColors[colorIndex]
                : fixedColors[0]
        }
    }

    static func applicationPreviewMaximumExtraWidth(
        sizeScale: CGFloat,
        iconCount: Int
    ) -> CGFloat {
        guard iconCount > 0 else { return 0 }
        let targetSize = StatusApplicationPreviewLayout.targetSize(
            iconCount: iconCount,
            scale: sizeScale
        )
        return max(
            targetSize.width * 1.055
                - StatusItemArtwork.dotDiameter(sizeScale: sizeScale),
            0
        )
    }

    func update(
        pill: StatusPillFrame?,
        activeIndex: Int? = nil,
        transitionSourceIndex: Int? = nil,
        interruptedTransitionPresentation:
            StatusInterruptedTransitionPresentation? = nil,
        hoverScales: [Int: CGSize] = [:],
        presentation: StatusArtworkPresentation = .identity,
        applicationPreviewFrame: StatusApplicationPreviewFrame = .hidden,
        applicationPreviewTracksPill: Bool = false
    ) {
        self.pill = pill
        self.activeIndex = activeIndex.flatMap {
            (0..<count).contains($0) ? $0 : nil
        }
        self.transitionSourceIndex = transitionSourceIndex.flatMap {
            (0..<count).contains($0) ? $0 : nil
        }
        self.interruptedTransitionPresentation =
            interruptedTransitionPresentation
        self.hoverScales = hoverScales.filter {
            (0..<count).contains($0.key)
                && $0.value.width > 0
                && $0.value.height > 0
        }
        self.presentation = presentation
        self.applicationPreviewFrame = applicationPreviewFrame
        self.applicationPreviewTracksPill =
            applicationPreviewTracksPill
        redraw()
    }

    func transitionPresentationSnapshot(
        for pill: StatusPillFrame
    ) -> StatusInterruptedTransitionPresentation? {
        if
            let interruptedTransitionPresentation,
            let activeIndex
        {
            return resolvedInterruptedTransitionPresentation(
                from: interruptedTransitionPresentation,
                targetIndex: activeIndex,
                progress: pill.progress
            )
        }

        guard
            let pillIndex = activeIndex ?? inferredIndex(for: pill),
            indicatorKinds.indices.contains(pillIndex)
        else { return nil }

        let transition = transitionState(for: pill)
        let pillAppearance: StatusResolvedPillAppearance
        if let transition {
            pillAppearance = resolvedTransitioningPillAppearance(
                sourceIndex: transition.sourceIndex,
                targetIndex: transition.targetIndex,
                progress: transition.progress
            )
        } else {
            pillAppearance = restingPillAppearance(at: pillIndex)
        }

        let hiddenActiveIndex = transition == nil ? pillIndex : nil
        let inactiveIndicators = (0..<count).map { index in
            if index == hiddenActiveIndex {
                return StatusInactiveIndicatorAppearance(
                    opacity: 0,
                    scale: 0.58
                )
            }
            let presentation = inactivePresentation(
                at: index,
                transition: transition
            )
            return StatusInactiveIndicatorAppearance(
                opacity: presentation.opacity,
                scale: presentation.scale
            )
        }

        return StatusInterruptedTransitionPresentation(
            pill: pillAppearance,
            inactiveIndicators: inactiveIndicators,
            applicationPreviewBaseSize: applicationPreviewBaseSize(
                pill: pill,
                pillIndex: pillIndex,
                transition: transition
            )
        )
    }

    func resolvedInterruptedTransitionPresentation(
        from initial: StatusInterruptedTransitionPresentation,
        targetIndex: Int,
        progress: CGFloat
    ) -> StatusInterruptedTransitionPresentation {
        guard indicatorKinds.indices.contains(targetIndex) else {
            return initial
        }
        let progress = min(max(progress, 0), 1)
        let targetPill = restingPillAppearance(at: targetIndex)
        let inactiveIndicators = (0..<count).map { index in
            let initialIndicator = initial.inactiveIndicators.indices
                .contains(index)
                ? initial.inactiveIndicators[index]
                : StatusInactiveIndicatorAppearance(
                    opacity: 1,
                    scale: 1
                )
            let targetIndicator = StatusInactiveIndicatorAppearance(
                opacity: index == targetIndex ? 0 : 1,
                scale: index == targetIndex ? 0.58 : 1
            )
            return StatusInactiveIndicatorAppearance(
                opacity: interpolate(
                    initialIndicator.opacity,
                    targetIndicator.opacity,
                    progress
                ),
                scale: interpolate(
                    initialIndicator.scale,
                    targetIndicator.scale,
                    progress
                )
            )
        }

        let previewBaseSize: NSSize?
        if
            let initialPreviewBaseSize =
                initial.applicationPreviewBaseSize,
            let applicationPreviewIndex
        {
            let targetPreviewBaseSize =
                applicationPreviewIndex == targetIndex
                    ? activePreviewBaseSize
                    : inactivePreviewBaseSize(
                        at: applicationPreviewIndex
                    )
            previewBaseSize = interpolatedPreviewBaseSize(
                from: initialPreviewBaseSize,
                to: targetPreviewBaseSize,
                progress: progress
            )
        } else {
            previewBaseSize = nil
        }

        return StatusInterruptedTransitionPresentation(
            pill: StatusResolvedPillAppearance(
                color: interpolatedColor(
                    from: initial.pill.color,
                    to: targetPill.color,
                    progress: progress
                ),
                desktopOpacity: interpolate(
                    initial.pill.desktopOpacity,
                    targetPill.desktopOpacity,
                    progress
                ),
                fullscreenOpacity: interpolate(
                    initial.pill.fullscreenOpacity,
                    targetPill.fullscreenOpacity,
                    progress
                )
            ),
            inactiveIndicators: inactiveIndicators,
            applicationPreviewBaseSize: previewBaseSize
        )
    }

    func indicatorIndex(atImageX x: CGFloat) -> Int? {
        let x = unscaledLayoutX(fromRenderedImageX: x)
        // Changing an NSStatusItem's width moves its local coordinate system.
        // Preserve the hovered identity across that relayout by accepting both
        // the expanding visual shape and the original indicator cell. Without
        // this, a stationary pointer can be classified as the next indicator
        // for one frame and immediately dismiss the preview.
        if let applicationPreviewIndex,
           let currentApplicationPreviewHitRange,
           currentApplicationPreviewHitRange.contains(x) {
            return applicationPreviewIndex
        }

        let centers = (0..<count).map {
            layoutCenterX(
                for: $0,
                extraWidth: currentApplicationPreviewExtraWidth
            )
        }
        guard
            let first = centers.first,
            let last = centers.last,
            x >= first - edgeItemWidth / 2,
            x < last + edgeItemWidth / 2
        else { return nil }

        return centers.enumerated().min {
            abs($0.element - x) < abs($1.element - x)
        }?.offset
    }

    func indicatorCenterX(at index: Int) -> CGFloat? {
        guard (0..<count).contains(index) else { return nil }
        // Pill motion is rendered inside the same content-scale transform as
        // the rest of the artwork. Keep its trajectory in layout coordinates;
        // returning an already-scaled value makes the moving pill jump when
        // the application preview changes the fitted content scale.
        return layoutCenterX(
            for: index,
            extraWidth: currentApplicationPreviewExtraWidth
        )
    }

    func renderedIndicatorCenterX(at index: Int) -> CGFloat? {
        guard (0..<count).contains(index) else { return nil }
        return renderedImageX(
            fromUnscaledLayoutX: layoutCenterX(
                for: index,
                extraWidth: currentApplicationPreviewExtraWidth
            )
        )
    }

    var applicationPreviewTargetExtraWidth: CGFloat {
        guard applicationPreviewIndex != nil else { return 0 }
        return max(applicationPreviewTargetSize.width - dotDiameter, 0)
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

        // Keep these pixels appearance-independent. A template image would be
        // re-tinted by AppKit while the menu bar itself crossfades between
        // Spaces, producing one mismatched frame during an active animation.
        let transition = transitionState(for: pill)
        let pillIndex = pill.map {
            activeIndex ?? inferredIndex(for: $0) ?? 0
        }
        let resolvedInterruptedPresentation:
            StatusInterruptedTransitionPresentation? = {
                guard
                    let initial = interruptedTransitionPresentation,
                    let pill,
                    let activeIndex
                else { return nil }
                return resolvedInterruptedTransitionPresentation(
                    from: initial,
                    targetIndex: activeIndex,
                    progress: pill.progress
                )
            }()
        let previewFollowsPill =
            applicationPreviewTracksPill && pill != nil
        let previewGeometry = applicationPreviewGeometry(
            pill: pill,
            pillIndex: pillIndex,
            transition: transition,
            baseSizeOverride:
                resolvedInterruptedPresentation?
                    .applicationPreviewBaseSize,
            followsPill: previewFollowsPill
        )
        currentApplicationPreviewExtraWidth = previewGeometry?.extraWidth ?? 0
        currentContentScale = fittedContentScale(
            extraWidth: currentApplicationPreviewExtraWidth
        )
        let outerPadding = max(
            baseStatusItemWidth - baseContentWidth,
            0
        )
        currentStatusItemWidth = outerPadding
            + (baseContentWidth + currentApplicationPreviewExtraWidth)
                * currentContentScale
        currentApplicationPreviewHitRange = previewGeometry.map {
            applicationPreviewHitRange(for: $0)
        }

        graphics.saveGState()
        defer { graphics.restoreGState() }
        graphics.setAlpha(min(max(presentation.opacity, 0), 1))
        let center = CGPoint(
            x: imageSize.width / 2,
            y: imageSize.height / 2
        )
        graphics.translateBy(x: center.x, y: center.y)
        graphics.scaleBy(
            x: max(presentation.scaleX * currentContentScale, 0.001),
            y: max(presentation.scaleY * currentContentScale, 0.001)
        )
        graphics.translateBy(x: -center.x, y: -center.y)

        // NSGraphicsContext already derives a 2x CTM from bitmap.size versus
        // pixelsWide/pixelsHigh. Scaling it again makes the artwork 4x and
        // clips the right-hand dots and pill at the image boundary.

        let hiddenActiveIndex =
            resolvedInterruptedPresentation == nil && transition == nil
            ? pill.flatMap { activeIndex ?? inferredIndex(for: $0) }
            : nil
        for index in 0..<count {
            guard
                index != hiddenActiveIndex,
                index != applicationPreviewIndex
                    || previewFollowsPill
            else { continue }
            let center = NSPoint(
                x: layoutCenterX(
                    for: index,
                    extraWidth: currentApplicationPreviewExtraWidth
                ),
                y: imageSize.height / 2
            )
            let presentation: (opacity: CGFloat, scale: CGFloat)
            if
                let resolvedInterruptedPresentation,
                resolvedInterruptedPresentation.inactiveIndicators.indices
                    .contains(index)
            {
                let resolved = resolvedInterruptedPresentation
                    .inactiveIndicators[index]
                presentation = (resolved.opacity, resolved.scale)
            } else {
                presentation = inactivePresentation(
                    at: index,
                    transition: transition
                )
            }
            drawInactiveIndicator(
                at: center,
                index: index,
                opacity: presentation.opacity,
                transitionScale: presentation.scale
            )
        }

        if
            let pill,
            let pillIndex,
            pillIndex != applicationPreviewIndex
                && !previewFollowsPill
        {
            let hoverScale = pillHoverScale(
                for: pillIndex,
                pill: pill
            )
            let activeSize = shapeStyle.activeIndicatorSize(
                sizeScale: sizeScale
            )

            // Hover belongs to the destination indicator, not to the temporary
            // liquid bridge. Scaling the complete bridge makes an edge-to-edge
            // continuous transition grow beyond the bitmap on both sides and
            // its rounded caps are then clipped by AppKit.
            let width = pill.width
                + activeSize.width * (hoverScale.width - 1)
            let height = pill.height
                + activeSize.height * (hoverScale.height - 1)
            let centerX = layoutX(
                forBaseContentX: pill.x - horizontalPadding,
                extraWidth: currentApplicationPreviewExtraWidth
            )
            let rect = NSRect(
                x: centerX - width / 2,
                y: (imageSize.height - height) / 2,
                width: width,
                height: height
            )
            if let resolvedInterruptedPresentation {
                drawResolvedPillAppearance(
                    in: rect,
                    appearance: resolvedInterruptedPresentation.pill,
                    waist: pill.waist
                )
            } else if let transition {
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

        if let previewGeometry, let applicationPreviewIndex {
            drawApplicationPreview(
                geometry: previewGeometry,
                index: applicationPreviewIndex,
                isActive: pillIndex == applicationPreviewIndex,
                followsPill: previewFollowsPill,
                pillIndex: pillIndex,
                pill: pill,
                transition: transition,
                resolvedInterruptedPresentation:
                    resolvedInterruptedPresentation
            )
        }
    }

    private struct ApplicationPreviewGeometry {
        let rect: NSRect
        let extraWidth: CGFloat
    }

    private var applicationPreviewTargetSize: NSSize {
        StatusApplicationPreviewLayout.targetSize(
            iconCount: applicationIcons.count,
            scale: applicationPreviewScale
        )
    }

    private var applicationIconSpacing: CGFloat {
        StatusApplicationPreviewLayout.iconSpacing
            * applicationPreviewScale
    }

    private func applicationPreviewGeometry(
        pill: StatusPillFrame?,
        pillIndex: Int?,
        transition: (sourceIndex: Int, targetIndex: Int, progress: CGFloat)?,
        baseSizeOverride: NSSize?,
        followsPill: Bool
    ) -> ApplicationPreviewGeometry? {
        guard let index = applicationPreviewIndex else { return nil }

        let baseSize: NSSize
        if followsPill, let pill {
            baseSize = NSSize(
                width: pill.width,
                height: pill.height
            )
        } else {
            baseSize = baseSizeOverride
                ?? applicationPreviewBaseSize(
                    pill: pill,
                    pillIndex: pillIndex,
                    transition: transition
                )
                ?? inactivePreviewBaseSize(at: index)
        }

        let expansion = max(applicationPreviewFrame.expansion, 0)
        let extraWidth = applicationPreviewTargetExtraWidth * expansion
        let heightProgress = min(expansion, 1)
        let width = baseSize.width
            + (applicationPreviewTargetSize.width - baseSize.width)
                * heightProgress
        var height = baseSize.height
            + (applicationPreviewTargetSize.height - baseSize.height)
                * heightProgress
        if expansion > 1 {
            height *= 1 - min((expansion - 1) * 0.55, 0.035)
        }
        let centerX: CGFloat
        if followsPill, let pill {
            centerX = layoutX(
                forBaseContentX: pill.x - horizontalPadding,
                extraWidth: extraWidth
            )
        } else {
            centerX = layoutCenterX(
                for: index,
                extraWidth: extraWidth
            )
        }
        let center = NSPoint(
            x: centerX,
            y: imageSize.height / 2
        )
        return ApplicationPreviewGeometry(
            rect: NSRect(
                x: center.x - width / 2,
                y: center.y - height / 2,
                width: width,
                height: height
            ),
            extraWidth: extraWidth
        )
    }

    private func applicationPreviewBaseSize(
        pill: StatusPillFrame?,
        pillIndex: Int?,
        transition: (sourceIndex: Int, targetIndex: Int, progress: CGFloat)?
    ) -> NSSize? {
        guard let index = applicationPreviewIndex else { return nil }

        if let transition, transition.sourceIndex == index {
            return interpolatedPreviewBaseSize(
                from: activePreviewBaseSize,
                to: inactivePreviewBaseSize(at: index),
                progress: smoothStep(transition.progress)
            )
        } else if let transition, transition.targetIndex == index {
            return interpolatedPreviewBaseSize(
                from: inactivePreviewBaseSize(at: index),
                to: activePreviewBaseSize,
                progress: smoothStep(transition.progress)
            )
        } else if let pill, pillIndex == index {
            let activeSize = shapeStyle.activeIndicatorSize(
                sizeScale: sizeScale
            )
            let hoverScale = pillHoverScale(for: index, pill: pill)
            return NSSize(
                width: pill.width
                    + activeSize.width * (hoverScale.width - 1),
                height: pill.height
                    + activeSize.height * (hoverScale.height - 1)
            )
        } else {
            let hoverScale = hoverScales[index]
                ?? CGSize(width: 1, height: 1)
            return NSSize(
                width: dotDiameter * hoverScale.width,
                height: dotDiameter * hoverScale.height
            )
        }
    }

    private var activePreviewBaseSize: NSSize {
        shapeStyle.activeIndicatorSize(sizeScale: sizeScale)
    }

    private func inactivePreviewBaseSize(at index: Int) -> NSSize {
        let hoverScale = hoverScales[index]
            ?? CGSize(width: 1, height: 1)
        return NSSize(
            width: dotDiameter * hoverScale.width,
            height: dotDiameter * hoverScale.height
        )
    }

    private func interpolatedPreviewBaseSize(
        from source: NSSize,
        to target: NSSize,
        progress: CGFloat
    ) -> NSSize {
        NSSize(
            width: source.width
                + (target.width - source.width) * progress,
            height: source.height
                + (target.height - source.height) * progress
        )
    }

    private func layoutCenterX(for index: Int, extraWidth: CGFloat) -> CGFloat {
        layoutX(
            forBaseContentX: edgeItemWidth / 2 + CGFloat(index) * itemWidth,
            extraWidth: extraWidth
        )
    }

    private func applicationPreviewHitRange(
        for geometry: ApplicationPreviewGeometry
    ) -> ClosedRange<CGFloat> {
        // The status item grows towards the leading edge. In image
        // coordinates, the indicator's original hit cell therefore shifts by
        // half the animated width even though the visual center stays stable.
        let shiftedCellCenter = geometry.rect.midX
            + geometry.extraWidth / 2
        let originalCell = NSRect(
            x: shiftedCellCenter - itemWidth / 2,
            y: 0,
            width: itemWidth,
            height: imageSize.height
        )
        let lowerBound = min(geometry.rect.minX, originalCell.minX)
        let upperBound = max(geometry.rect.maxX, originalCell.maxX)
        return lowerBound...upperBound
    }

    private func layoutX(
        forBaseContentX baseX: CGFloat,
        extraWidth: CGFloat
    ) -> CGFloat {
        let centeringInset = horizontalOverflowPadding
            + (applicationPreviewMaximumExtraWidth - extraWidth) / 2
        guard let previewIndex = applicationPreviewIndex else {
            return centeringInset + baseX
        }
        let previewBaseX = edgeItemWidth / 2
            + CGFloat(previewIndex) * itemWidth
        return centeringInset
            + baseX
            + Self.applicationPreviewLayoutShift(
                baseX: baseX,
                previewBaseX: previewBaseX,
                itemWidth: itemWidth,
                extraWidth: extraWidth
            )
    }

    /// Content on either side of an expanded preview still receives the full
    /// 0 / `extraWidth` displacement. A moving pill, however, can cross the
    /// preview cell between display-link frames, so its displacement must be
    /// continuous rather than switching discretely at the cell centre.
    static func applicationPreviewLayoutShift(
        baseX: CGFloat,
        previewBaseX: CGFloat,
        itemWidth: CGFloat,
        extraWidth: CGFloat
    ) -> CGFloat {
        guard itemWidth > 0, extraWidth > 0 else { return 0 }
        let progress = min(
            max(
                0.5 + (baseX - previewBaseX) / itemWidth,
                0
            ),
            1
        )
        return extraWidth * progress
    }

    private func fittedContentScale(extraWidth: CGFloat) -> CGFloat {
        guard let maximumVisibleContentWidth else { return 1 }
        let outerPadding = max(
            baseStatusItemWidth - baseContentWidth,
            0
        )
        let availableContentWidth = max(
            maximumVisibleContentWidth - outerPadding,
            0.01
        )
        return min(
            availableContentWidth
                / max(baseContentWidth + extraWidth, 0.01),
            1
        )
    }

    private func renderedImageX(
        fromUnscaledLayoutX x: CGFloat
    ) -> CGFloat {
        let centerX = imageSize.width / 2
        return centerX + (x - centerX) * currentContentScale
    }

    private func unscaledLayoutX(
        fromRenderedImageX x: CGFloat
    ) -> CGFloat {
        let centerX = imageSize.width / 2
        return centerX
            + (x - centerX) / max(currentContentScale, 0.01)
    }

    private func drawApplicationPreview(
        geometry: ApplicationPreviewGeometry,
        index: Int,
        isActive: Bool,
        followsPill: Bool,
        pillIndex: Int?,
        pill: StatusPillFrame?,
        transition: (
            sourceIndex: Int,
            targetIndex: Int,
            progress: CGFloat
        )?,
        resolvedInterruptedPresentation:
            StatusInterruptedTransitionPresentation?
    ) {
        // `StatusApplicationPreviewMotion` has already eased this value.
        // Re-easing it here made color lag behind geometry and icons around
        // both endpoints, which read as a short pause during hover.
        let appearanceProgress = min(
            max(applicationPreviewFrame.expansion, 0),
            1
        )
        if followsPill, let pill {
            if let resolvedInterruptedPresentation {
                drawResolvedPillAppearance(
                    in: geometry.rect,
                    appearance: resolvedInterruptedPresentation.pill,
                    waist: pill.waist
                )
            } else if let transition {
                drawTransitioningPill(
                    in: geometry.rect,
                    sourceIndex: transition.sourceIndex,
                    targetIndex: transition.targetIndex,
                    progress: transition.progress,
                    waist: pill.waist
                )
            } else if
                let pillIndex,
                indicatorKinds.indices.contains(pillIndex)
            {
                drawActiveIndicator(
                    in: geometry.rect,
                    kind: indicatorKinds[pillIndex],
                    color: indicatorColors[pillIndex],
                    waist: pill.waist
                )
            }
        } else {
            drawApplicationPreviewIndicator(
                in: geometry.rect,
                index: index,
                isActive: isActive,
                appearanceProgress: appearanceProgress
            )
        }

        let progress = min(
            max(applicationPreviewFrame.expansion, 0),
            1
        )
        let fullIconsWidth =
            CGFloat(applicationIcons.count) * applicationIconSize
            + CGFloat(max(applicationIcons.count - 1, 0))
                * applicationIconSpacing
        let horizontalInset =
            StatusApplicationPreviewLayout.horizontalInset
            * applicationPreviewScale * progress
        let verticalInset =
            StatusApplicationPreviewLayout.verticalInset
            * applicationPreviewScale * progress
        let availableWidth = max(
            geometry.rect.width - horizontalInset * 2,
            0
        )
        let availableHeight = max(
            geometry.rect.height - verticalInset * 2,
            0
        )
        let iconScale = min(
            min(
                availableWidth / max(fullIconsWidth, 0.001),
                availableHeight / max(applicationIconSize, 0.001)
            ),
            1
        )
        let iconSize = applicationIconSize * iconScale
        let iconSpacing = applicationIconSpacing * iconScale
        let totalWidth = CGFloat(applicationIcons.count) * iconSize
            + CGFloat(max(applicationIcons.count - 1, 0))
                * iconSpacing
        let baseOpacity = min(
            max(applicationPreviewFrame.iconOpacity, 0),
            1
        )
        // Icons shrink into the same shape while fading slightly faster than
        // its background. This prevents a bright afterimage outside a pill
        // that has already become narrower than the icon group.
        let opacity = baseOpacity * baseOpacity
            * min(iconScale * 1.4, 1)
        guard
            opacity > 0.001,
            iconSize > 0.001,
            !applicationIcons.isEmpty
        else { return }

        var x = geometry.rect.midX - totalWidth / 2
        let y = geometry.rect.midY - iconSize / 2
        for icon in applicationIcons {
            icon.draw(
                in: NSRect(
                    x: x,
                    y: y,
                    width: iconSize,
                    height: iconSize
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: opacity,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            x += iconSize + iconSpacing
        }
    }

    private func drawApplicationPreviewIndicator(
        in rect: NSRect,
        index: Int,
        isActive: Bool,
        appearanceProgress: CGFloat
    ) {
        let color = indicatorColors[index]
        let progress = min(max(appearanceProgress, 0), 1)
        if indicatorKinds[index].isFullscreen {
            let inactiveLineWidth = fullscreenOutlineWidth
                * (increasedContrast ? 1.12 : 1)
            let activeLineWidth = fullscreenOutlineWidth
                * (increasedContrast ? 1.68 : 1.5)
            let initialOpacity = isActive
                ? 1
                : inactiveFullscreenOpacity
            let initialLineWidth = isActive
                ? activeLineWidth
                : inactiveLineWidth
            drawHollowIndicator(
                in: rect,
                color: color,
                strokeOpacity: initialOpacity
                    + (1 - initialOpacity) * progress,
                lineWidth: initialLineWidth
                    + (activeLineWidth - initialLineWidth) * progress,
                isFullscreen: true
            )
            return
        }

        let initialOpacity = isActive ? 1 : inactiveDesktopOpacity
        drawFilledIndicator(
            in: rect,
            color: color,
            fillOpacity: initialOpacity
                + (1 - initialOpacity) * progress
        )
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
                strokeOpacity: inactiveFullscreenOpacity * opacity,
                lineWidth: fullscreenOutlineWidth
                    * (increasedContrast ? 1.12 : 1),
                isFullscreen: true
            )
        } else {
            drawFilledIndicator(
                in: rect,
                color: color,
                fillOpacity: inactiveDesktopOpacity * opacity
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
        drawResolvedPillAppearance(
            in: rect,
            appearance: resolvedTransitioningPillAppearance(
                sourceIndex: sourceIndex,
                targetIndex: targetIndex,
                progress: progress
            ),
            waist: waist
        )
    }

    private func restingPillAppearance(
        at index: Int
    ) -> StatusResolvedPillAppearance {
        StatusResolvedPillAppearance(
            color: indicatorColors[index],
            desktopOpacity: indicatorKinds[index].isFullscreen ? 0 : 1,
            fullscreenOpacity: indicatorKinds[index].isFullscreen ? 1 : 0
        )
    }

    private func resolvedTransitioningPillAppearance(
        sourceIndex: Int,
        targetIndex: Int,
        progress: CGFloat
    ) -> StatusResolvedPillAppearance {
        let visualProgress = smoothStep(
            remap(progress, from: 0.20, to: 0.80)
        )
        let sourceKind = indicatorKinds[sourceIndex]
        let targetKind = indicatorKinds[targetIndex]
        let color = interpolatedColor(
            from: indicatorColors[sourceIndex],
            to: indicatorColors[targetIndex],
            progress: visualProgress
        )

        if sourceKind.isFullscreen == targetKind.isFullscreen {
            return StatusResolvedPillAppearance(
                color: color,
                desktopOpacity: targetKind.isFullscreen ? 0 : 1,
                fullscreenOpacity: targetKind.isFullscreen ? 1 : 0
            )
        }

        let sourceDesktopOpacity = sourceKind.isFullscreen
            ? 0
            : 1 - visualProgress
        let targetDesktopOpacity = targetKind.isFullscreen
            ? 0
            : visualProgress
        let sourceFullscreenOpacity = sourceKind.isFullscreen
            ? 1 - visualProgress
            : 0
        let targetFullscreenOpacity = targetKind.isFullscreen
            ? visualProgress
            : 0
        return StatusResolvedPillAppearance(
            color: color,
            desktopOpacity:
                sourceDesktopOpacity + targetDesktopOpacity,
            fullscreenOpacity:
                sourceFullscreenOpacity + targetFullscreenOpacity
        )
    }

    private func drawResolvedPillAppearance(
        in rect: NSRect,
        appearance: StatusResolvedPillAppearance,
        waist: CGFloat
    ) {
        // A desktop fill and a full-screen inner outline dissolve through one
        // another while sharing the exact same liquid silhouette.
        drawActiveIndicator(
            in: rect,
            kind: .desktop(colorIndex: 0),
            color: appearance.color,
            opacity: appearance.desktopOpacity,
            waist: waist
        )
        drawActiveIndicator(
            in: rect,
            kind: .fullscreen(colorIndex: 0),
            color: appearance.color,
            opacity: appearance.fullscreenOpacity,
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
                lineWidth: fullscreenOutlineWidth
                    * (increasedContrast ? 1.68 : 1.5),
                waist: waist,
                isFullscreen: true
            )
        } else {
            drawFilledIndicator(
                in: rect,
                color: color,
                fillOpacity: opacity,
                waist: waist
            )
        }
    }

    private func drawHollowIndicator(
        in rect: NSRect,
        color: NSColor,
        strokeOpacity: CGFloat,
        lineWidth: CGFloat,
        waist: CGFloat = 0,
        isFullscreen: Bool = false
    ) {
        drawOutline(
            in: rect,
            color: color.withAlphaComponent(strokeOpacity),
            lineWidth: lineWidth,
            waist: waist,
            isFullscreen: isFullscreen
        )
    }

    private func drawFilledIndicator(
        in rect: NSRect,
        color: NSColor,
        fillOpacity: CGFloat,
        waist: CGFloat = 0
    ) {
        color.withAlphaComponent(fillOpacity).setFill()
        indicatorPath(in: rect, waist: waist).fill()
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
                remap(transition.progress, from: 0.56, to: 0.82)
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

    private func interpolate(
        _ source: CGFloat,
        _ target: CGFloat,
        _ progress: CGFloat
    ) -> CGFloat {
        source + (target - source) * progress
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
        waist: CGFloat = 0,
        isFullscreen: Bool = false
    ) {
        let inset = isFullscreen
            ? lineWidth
            : lineWidth / 2
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
            localCenter - edgeItemWidth / 2
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

    private var inactiveDesktopOpacity: CGFloat {
        increasedContrast ? 0.55 : 0.50
    }

    private var inactiveFullscreenOpacity: CGFloat {
        increasedContrast ? 0.72 : 0.46
    }

    private var fullscreenOutlineWidth: CGFloat {
        max(1.0 * sizeScale, 1)
    }

}
