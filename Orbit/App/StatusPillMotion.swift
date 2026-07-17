import Foundation

struct StatusPillFrame: Equatable, Sendable {
    let x: CGFloat
    let width: CGFloat
    let height: CGFloat
    let isComplete: Bool

    nonisolated static func resting(at x: CGFloat) -> Self {
        Self(x: x, width: 12, height: 7, isComplete: true)
    }
}

struct StatusPillMotion {
    let fromX: CGFloat
    let toX: CGFloat
    let initialWidth: CGFloat
    let initialHeight: CGFloat
    let startTime: TimeInterval
    let duration: TimeInterval

    init(
        fromX: CGFloat,
        toX: CGFloat,
        initialWidth: CGFloat = 12,
        initialHeight: CGFloat = 7,
        startTime: TimeInterval
    ) {
        self.fromX = fromX
        self.toX = toX
        self.initialWidth = initialWidth
        self.initialHeight = initialHeight
        self.startTime = startTime

        let distance = abs(toX - fromX)
        let crossedSpaces = max(distance / StatusItemArtwork.itemWidth, 1)
        duration = 0.235 + min(TimeInterval(crossedSpaces - 1) * 0.015, 0.05)
    }

    func frame(at timestamp: TimeInterval) -> StatusPillFrame {
        let rawProgress = CGFloat((timestamp - startTime) / duration)
        if rawProgress >= 0.999_999 {
            return .resting(at: toX)
        }
        if rawProgress <= 0 {
            return StatusPillFrame(
                x: fromX,
                width: initialWidth,
                height: initialHeight,
                isComplete: false
            )
        }

        let progress = min(max(rawProgress, 0), 1)
        let x = interpolate(fromX, toX, cubicBezierProgress(progress))
        let crossedSpaces = max(
            abs(toX - fromX) / StatusItemArtwork.itemWidth,
            1
        )
        let stretchedWidth = 18.8 + min(crossedSpaces - 1, 4) * 0.4

        return StatusPillFrame(
            x: x,
            width: phasedValue(
                progress: progress,
                values: [initialWidth, stretchedWidth, 10.9, 12]
            ),
            height: phasedValue(
                progress: progress,
                values: [initialHeight, 5.9, 7.65, 7]
            ),
            isComplete: false
        )
    }

    private func phasedValue(progress: CGFloat, values: [CGFloat]) -> CGFloat {
        let keyTimes: [CGFloat] = [0, 0.34, 0.72, 1]
        let phase = progress < keyTimes[1] ? 0 : progress < keyTimes[2] ? 1 : 2
        let local = (progress - keyTimes[phase])
            / (keyTimes[phase + 1] - keyTimes[phase])
        let clamped = min(max(local, 0), 1)
        return interpolate(
            values[phase],
            values[phase + 1],
            clamped * clamped * (3 - 2 * clamped)
        )
    }

    private func cubicBezierProgress(_ progress: CGFloat) -> CGFloat {
        let x1: CGFloat = 0.20
        let y1: CGFloat = 0.68
        let x2: CGFloat = 0.25
        let y2: CGFloat = 1
        var parameter = progress

        for _ in 0..<6 {
            let error = cubic(parameter, x1, x2) - progress
            let slope = cubicDerivative(parameter, x1, x2)
            guard abs(slope) > 0.0001 else { break }
            parameter = min(max(parameter - error / slope, 0), 1)
        }
        return cubic(parameter, y1, y2)
    }

    private func cubic(_ value: CGFloat, _ first: CGFloat, _ second: CGFloat) -> CGFloat {
        let inverse = 1 - value
        return 3 * inverse * inverse * value * first
            + 3 * inverse * value * value * second
            + value * value * value
    }

    private func cubicDerivative(
        _ value: CGFloat,
        _ first: CGFloat,
        _ second: CGFloat
    ) -> CGFloat {
        let inverse = 1 - value
        return 3 * inverse * inverse * first
            + 6 * inverse * value * (second - first)
            + 3 * value * value * (1 - second)
    }

    private func interpolate(
        _ start: CGFloat,
        _ end: CGFloat,
        _ progress: CGFloat
    ) -> CGFloat {
        start + (end - start) * progress
    }
}
