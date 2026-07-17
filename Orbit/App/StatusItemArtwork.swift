import AppKit

enum StatusItemArtwork {
    nonisolated static let itemWidth: CGFloat = 14
    nonisolated static let horizontalPadding: CGFloat = 4
    nonisolated static let imageHeight: CGFloat = 22
    nonisolated static let dotDiameter: CGFloat = 4.5

    static func preferredWidth(for count: Int) -> CGFloat {
        CGFloat(normalizedCount(count)) * itemWidth + horizontalPadding * 2
    }

    static func centerX(for index: Int) -> CGFloat {
        horizontalPadding + CGFloat(index) * itemWidth + itemWidth / 2
    }

    private static func normalizedCount(_ count: Int) -> Int {
        max(count, 1)
    }
}
