import AppKit

enum StatusItemArtwork {
    nonisolated static let itemWidth: CGFloat = 14
    nonisolated static let horizontalPadding: CGFloat = 4
    nonisolated static let imageHeight: CGFloat = 22
    nonisolated static let dotDiameter: CGFloat = 4.5

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
