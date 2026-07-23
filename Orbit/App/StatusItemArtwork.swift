import AppKit

enum StatusItemArtwork {
    nonisolated static let itemWidth: CGFloat = 14
    nonisolated static let horizontalPadding: CGFloat = 4
    nonisolated static let imageHeight: CGFloat = 22
    nonisolated static let dotDiameter: CGFloat = 4.5
    /// Keeps a crowded status item from being evicted by macOS when the user
    /// creates many Spaces. Regular configurations retain their exact size.
    nonisolated static let maximumStatusItemWidth: CGFloat = 168

    nonisolated static func itemWidth(
        sizeScale: CGFloat,
        spacingScale: CGFloat
    ) -> CGFloat {
        itemWidth * sizeScale * spacingScale
    }

    /// Width occupied by an edge indicator before any inter-item spacing is
    /// applied. Keeping this independent from `spacingScale` prevents the
    /// spacing setting from growing the leading and trailing margins.
    nonisolated static func edgeItemWidth(sizeScale: CGFloat) -> CGFloat {
        itemWidth * sizeScale
    }

    nonisolated static func horizontalPadding(sizeScale: CGFloat) -> CGFloat {
        horizontalPadding * sizeScale
    }

    nonisolated static func dotDiameter(sizeScale: CGFloat) -> CGFloat {
        dotDiameter * sizeScale
    }

    nonisolated static func preferredWidth(
        for count: Int,
        sizeScale: CGFloat = 1,
        spacingScale: CGFloat = 1
    ) -> CGFloat {
        contentWidth(
            for: count,
            sizeScale: sizeScale,
            spacingScale: spacingScale
        ) + horizontalPadding(sizeScale: sizeScale) * 2
    }

    nonisolated static func contentWidth(
        for count: Int,
        sizeScale: CGFloat = 1,
        spacingScale: CGFloat = 1
    ) -> CGFloat {
        let count = normalizedCount(count)
        return edgeItemWidth(sizeScale: sizeScale)
            + CGFloat(count - 1) * itemWidth(
                sizeScale: sizeScale,
                spacingScale: spacingScale
            )
    }

    nonisolated static func fittedSizeScale(
        for count: Int,
        requestedSizeScale: CGFloat,
        spacingScale: CGFloat,
        maximumWidth: CGFloat = maximumStatusItemWidth
    ) -> CGFloat {
        let requestedSizeScale = max(requestedSizeScale, 0.01)
        let unitWidth = preferredWidth(
            for: count,
            sizeScale: 1,
            spacingScale: spacingScale
        )
        guard unitWidth > 0, maximumWidth > 0 else {
            return requestedSizeScale
        }
        return min(requestedSizeScale, maximumWidth / unitWidth)
    }

    nonisolated static func centerX(
        for index: Int,
        sizeScale: CGFloat = 1,
        spacingScale: CGFloat = 1
    ) -> CGFloat {
        let spacing = itemWidth(
            sizeScale: sizeScale,
            spacingScale: spacingScale
        )
        return horizontalPadding(sizeScale: sizeScale)
            + edgeItemWidth(sizeScale: sizeScale) / 2
            + CGFloat(index) * spacing
    }

    nonisolated private static func normalizedCount(_ count: Int) -> Int {
        max(count, 1)
    }
}
