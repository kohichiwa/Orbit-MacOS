import AppKit

enum StatusItemArtwork {
    nonisolated static let visualScale: CGFloat = 1.21
    nonisolated static let itemWidth: CGFloat = 14 * visualScale
    nonisolated static let horizontalPadding: CGFloat = 4 * visualScale
    nonisolated static let imageHeight: CGFloat = 22
    nonisolated static let dotDiameter: CGFloat = 4.5 * visualScale

    nonisolated static func scaled(_ value: CGFloat) -> CGFloat {
        value * visualScale
    }

    nonisolated static func scaled(_ value: CGFloat, sizeScale: CGFloat) -> CGFloat {
        value * visualScale * sizeScale
    }

    nonisolated static func itemWidth(
        sizeScale: CGFloat,
        spacingScale: CGFloat
    ) -> CGFloat {
        14 * visualScale * sizeScale * spacingScale
    }

    nonisolated static func horizontalPadding(sizeScale: CGFloat) -> CGFloat {
        4 * visualScale * sizeScale
    }

    static func preferredWidth(for count: Int) -> CGFloat {
        CGFloat(normalizedCount(count)) * itemWidth + horizontalPadding * 2
    }

    static func preferredWidth(
        for count: Int,
        sizeScale: CGFloat,
        spacingScale: CGFloat
    ) -> CGFloat {
        CGFloat(normalizedCount(count)) * itemWidth(
            sizeScale: sizeScale,
            spacingScale: spacingScale
        ) + horizontalPadding(sizeScale: sizeScale) * 2
    }

    static func centerX(for index: Int) -> CGFloat {
        horizontalPadding + CGFloat(index) * itemWidth + itemWidth / 2
    }

    private static func normalizedCount(_ count: Int) -> Int {
        max(count, 1)
    }
}
