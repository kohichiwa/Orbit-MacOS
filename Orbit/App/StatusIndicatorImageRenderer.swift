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
    private let bitmap: NSBitmapImageRep
    private let accentColor: NSColor
    private let scale: CGFloat = 2

    init(count: Int, accentColor: NSColor = .controlAccentColor) {
        self.count = max(count, 1)
        self.accentColor = Self.fixedSRGBColor(from: accentColor)
        imageSize = NSSize(
            width: CGFloat(self.count) * StatusItemArtwork.itemWidth,
            height: StatusItemArtwork.imageHeight
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

    func update(pill: StatusPillFrame?) {
        self.pill = pill
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

        // NSGraphicsContext already derives a 2x CTM from bitmap.size versus
        // pixelsWide/pixelsHigh. Scaling it again makes the artwork 4x and
        // clips the right-hand dots and pill at the image boundary.

        // Keep these pixels appearance-independent. A template image would be
        // re-tinted by AppKit while the menu bar itself crossfades between
        // Spaces, producing one mismatched frame during an active animation.
        accentColor.withAlphaComponent(0.55).setFill()
        for index in 0..<count {
            let center = NSPoint(
                x: CGFloat(index) * StatusItemArtwork.itemWidth
                    + StatusItemArtwork.itemWidth / 2,
                y: imageSize.height / 2
            )
            let diameter = StatusItemArtwork.dotDiameter
            NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
            ).fill()
        }

        guard let pill else { return }
        accentColor.setFill()
        let centerX = pill.x - StatusItemArtwork.horizontalPadding
        let rect = NSRect(
            x: centerX - pill.width / 2,
            y: (imageSize.height - pill.height) / 2,
            width: pill.width,
            height: pill.height
        )
        NSBezierPath(
            roundedRect: rect,
            xRadius: pill.height / 2,
            yRadius: pill.height / 2
        ).fill()
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
}
