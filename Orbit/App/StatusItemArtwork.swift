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
        CGFloat(normalizedCount(count)) * itemWidth(
            sizeScale: sizeScale,
            spacingScale: spacingScale
        ) + horizontalPadding(sizeScale: sizeScale) * 2
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
        let width = itemWidth(
            sizeScale: sizeScale,
            spacingScale: spacingScale
        )
        return horizontalPadding(sizeScale: sizeScale)
            + CGFloat(index) * width
            + width / 2
    }

    nonisolated private static func normalizedCount(_ count: Int) -> Int {
        max(count, 1)
    }
}
