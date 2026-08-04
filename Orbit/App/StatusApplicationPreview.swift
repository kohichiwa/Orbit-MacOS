import AppKit

enum StatusApplicationPreviewLayout {
    nonisolated static let maximumIconCount = 12
    nonisolated static let demoMaximumContentWidth: CGFloat = 484
    nonisolated static let iconSize: CGFloat = 16
    nonisolated static let iconSpacing: CGFloat = 6
    nonisolated static let horizontalInset: CGFloat = 9.5
    nonisolated static let verticalInset: CGFloat = 3

    nonisolated static var pillHeight: CGFloat {
        iconSize + verticalInset * 2
    }

    nonisolated static func targetSize(
        iconCount: Int,
        scale: CGFloat
    ) -> NSSize {
        guard iconCount > 0 else { return .zero }
        let scale = max(scale, 0.01)
        let iconsWidth = CGFloat(iconCount) * iconSize
            + CGFloat(max(iconCount - 1, 0)) * iconSpacing
        let height = pillHeight
        return NSSize(
            width: max(
                iconsWidth + horizontalInset * 2,
                height
            ) * scale,
            height: height * scale
        )
    }
}

@MainActor
struct SpaceApplicationPresentation {
    struct VisualIdentity: Equatable {
        let applicationIdentity: String
        let iconRevision: UInt64
    }

    let identity: String
    let name: String
    let icon: NSImage
    let iconRevision: UInt64

    var visualIdentity: VisualIdentity {
        VisualIdentity(
            applicationIdentity: identity,
            iconRevision: iconRevision
        )
    }
}

@MainActor
enum SpaceApplicationPresentationFactory {
    enum IconResolution {
        case statusItem
        case demo

        var pointSize: NSSize {
            switch self {
            case .statusItem:
                return NSSize(width: 32, height: 32)
            case .demo:
                return NSSize(width: 64, height: 64)
            }
        }

        var pixelLength: Int {
            switch self {
            case .statusItem:
                return 64
            case .demo:
                return 256
            }
        }
    }

    static func presentations(
        for processIdentifiers: [pid_t],
        maximumCount: Int? = nil,
        iconResolution: IconResolution = .statusItem
    ) -> [SpaceApplicationPresentation] {
        var seenApplications = Set<String>()
        var presentations: [SpaceApplicationPresentation] = []
        for processIdentifier in processIdentifiers {
            guard
                let application = NSRunningApplication(
                    processIdentifier: processIdentifier
                ),
                !application.isTerminated,
                application.activationPolicy == .regular
            else { continue }
            let identity = application.bundleIdentifier
                ?? application.executableURL?.standardizedFileURL.path
                ?? application.localizedName?.lowercased()
                ?? "pid:\(processIdentifier)"
            guard seenApplications.insert(identity).inserted else {
                continue
            }
            let name = application.localizedName
                ?? application.bundleIdentifier
                ?? OrbitL10n.text(
                    "status.application.unknown",
                    fallback: "Application"
                )
            // NSWorkspace is the public system icon service on every supported
            // macOS release. On newer systems it resolves the icon appearance
            // chosen by the user; on macOS 14–15 it returns the traditional
            // application icon without requiring an availability branch.
            let sourceIcon = application.bundleURL.map {
                NSWorkspace.shared.icon(forFile: $0.path)
            } ?? application.icon
            let icon = sourceIcon
                ?? NSImage(
                    systemSymbolName: "app",
                    accessibilityDescription: name
                )
            guard
                let icon,
                let preparedIcon = prepareIcon(
                    icon,
                    appearance: NSApp.effectiveAppearance,
                    resolution: iconResolution
                )
            else { continue }
            presentations.append(
                SpaceApplicationPresentation(
                    identity: identity,
                    name: name,
                    icon: preparedIcon.image,
                    iconRevision: preparedIcon.revision
                )
            )
            if let maximumCount,
               presentations.count >= maximumCount {
                break
            }
        }
        return presentations
    }

    /// Orbit ultimately composites app icons into its own bitmap. Preparing a
    /// small 2x representation once per hover refresh avoids repeatedly
    /// resampling a 1024-point application icon on every 60/120 Hz frame and
    /// gives the state machine a cheap content revision for appearance changes.
    static func prepareIcon(
        _ source: NSImage,
        appearance: NSAppearance,
        resolution: IconResolution = .statusItem
    ) -> (image: NSImage, revision: UInt64)? {
        let preparedIconPointSize = resolution.pointSize
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: resolution.pixelLength,
            pixelsHigh: resolution.pixelLength,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = preparedIconPointSize
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            context.cgContext.clear(
                CGRect(
                    origin: .zero,
                    size: preparedIconPointSize
                )
            )
            source.draw(
                in: CGRect(
                    origin: .zero,
                    size: preparedIconPointSize
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: false,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.bitmapData else { return nil }
        let byteCount = bitmap.bytesPerRow * bitmap.pixelsHigh
        var revision: UInt64 = 1_469_598_103_934_665_603
        for byte in UnsafeBufferPointer(
            start: data,
            count: byteCount
        ) {
            revision ^= UInt64(byte)
            revision &*= 1_099_511_628_211
        }

        let image = NSImage(size: preparedIconPointSize)
        image.addRepresentation(bitmap)
        image.cacheMode = .never
        image.isTemplate = false
        return (image, revision)
    }
}

struct StatusApplicationPreviewFrame: Equatable {
    let expansion: CGFloat
    let iconOpacity: CGFloat
    let isComplete: Bool

    nonisolated static let hidden = Self(
        expansion: 0,
        iconOpacity: 0,
        isComplete: true
    )

    nonisolated static let visible = Self(
        expansion: 1,
        iconOpacity: 1,
        isComplete: true
    )
}

/// A compact, interruptible expansion used for the application-preview pill.
/// Expansion and icon alpha stay on the same smooth profile so hover feedback
/// appears as one continuous animation.
struct StatusApplicationPreviewMotion {
    let isPresenting: Bool
    let fromFrame: StatusApplicationPreviewFrame
    let startTime: TimeInterval
    let duration: TimeInterval

    init(
        isPresenting: Bool,
        fromFrame: StatusApplicationPreviewFrame,
        startTime: TimeInterval,
        fullDuration: TimeInterval? = nil
    ) {
        self.isPresenting = isPresenting
        self.fromFrame = fromFrame
        self.startTime = startTime
        let fullDuration = fullDuration ?? (
            isPresenting
                ? OrbitMotion.applicationPreviewEnterDuration
                : OrbitMotion.applicationPreviewExitDuration
        )
        let remainingDistance = isPresenting
            ? max(1 - fromFrame.expansion, 0)
            : max(fromFrame.expansion, 0)
        // Interrupted hover motion keeps approximately the same velocity
        // instead of replaying the full animation over a tiny distance.
        duration = max(
            fullDuration * TimeInterval(remainingDistance),
            min(fullDuration, 0.05)
        )
    }

    func frame(at timestamp: TimeInterval) -> StatusApplicationPreviewFrame {
        let rawProgress = CGFloat((timestamp - startTime) / duration)
        // Floating-point addition at an exact logical end time can land a few
        // ulps below 1. Treat that as complete so the last display-link frame
        // always settles to the stable resting geometry.
        guard rawProgress < 0.999_999 else {
            return isPresenting ? .visible : .hidden
        }
        guard rawProgress > 0 else { return fromFrame }
        let progress = min(max(rawProgress, 0), 1)
        // Cubic smoothstep retains zero-slope endpoints without the almost
        // stationary opening and closing frames of quintic smootherstep.
        // Those tiny deltas read as a micro-stall on compact menu-bar artwork.
        let easedProgress = smoothStep(progress)

        if isPresenting {
            let remaining = max(1 - fromFrame.expansion, 0)
            let expansion = fromFrame.expansion + remaining * easedProgress
            return StatusApplicationPreviewFrame(
                expansion: expansion,
                iconOpacity: fromFrame.iconOpacity
                    + (1 - fromFrame.iconOpacity) * easedProgress,
                isComplete: false
            )
        }

        let collapse = easedProgress
        return StatusApplicationPreviewFrame(
            expansion: fromFrame.expansion * (1 - collapse),
            iconOpacity: fromFrame.iconOpacity * (1 - collapse),
            isComplete: false
        )
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
