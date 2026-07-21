import Foundation

struct StatusPillFrame: Equatable, Sendable {
    let x: CGFloat
    let width: CGFloat
    let height: CGFloat
    /// Normalized progress of the current morph. Resting artwork is always 1.
    let progress: CGFloat
    let isComplete: Bool

    nonisolated static func resting(
        at x: CGFloat,
        sizeScale: CGFloat = 1
    ) -> Self {
        Self(
            x: x,
            width: 12 * sizeScale,
            height: 7 * sizeScale,
            progress: 1,
            isComplete: true
        )
    }
}

enum IndicatorRefreshTiming {
    nonisolated static let disappearDuration: TimeInterval = 0.14
    nonisolated static let appearDuration: TimeInterval = 0.24
    nonisolated static let totalDuration = disappearDuration + appearDuration
}

struct StatusArtworkPresentation: Equatable, Sendable {
    let opacity: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat

    nonisolated static let identity = Self(
        opacity: 1,
        scaleX: 1,
        scaleY: 1
    )
}

struct StatusArtworkRefreshFrame: Equatable, Sendable {
    let presentation: StatusArtworkPresentation
    let shouldApplySettings: Bool
    let isComplete: Bool
}

/// A short two-phase refresh used when the indicator layout or motion style
/// changes. The old artwork disappears first, the renderer is exchanged only
/// while fully hidden, and the new artwork then returns with a restrained,
/// nonbouncing liquid deformation.
struct StatusArtworkRefreshMotion {
    let startTime: TimeInterval
    let initialPresentation: StatusArtworkPresentation

    func frame(at timestamp: TimeInterval) -> StatusArtworkRefreshFrame {
        let elapsed = max(timestamp - startTime, 0)
        guard elapsed < IndicatorRefreshTiming.totalDuration - 0.000_001 else {
            return StatusArtworkRefreshFrame(
                presentation: .identity,
                shouldApplySettings: true,
                isComplete: true
            )
        }

        if elapsed < IndicatorRefreshTiming.disappearDuration {
            let progress = CGFloat(
                elapsed / IndicatorRefreshTiming.disappearDuration
            )
            let eased = smootherStep(progress)
            return StatusArtworkRefreshFrame(
                presentation: StatusArtworkPresentation(
                    opacity: interpolate(
                        initialPresentation.opacity,
                        0,
                        eased
                    ),
                    scaleX: interpolate(
                        initialPresentation.scaleX,
                        0.92,
                        eased
                    ),
                    scaleY: interpolate(
                        initialPresentation.scaleY,
                        0.82,
                        eased
                    )
                ),
                shouldApplySettings: false,
                isComplete: false
            )
        }

        let progress = CGFloat(
            (elapsed - IndicatorRefreshTiming.disappearDuration)
                / IndicatorRefreshTiming.appearDuration
        )
        let eased = smootherStep(progress)
        return StatusArtworkRefreshFrame(
            presentation: StatusArtworkPresentation(
                opacity: eased,
                scaleX: 0.92 + 0.08 * eased,
                scaleY: 0.82 + 0.18 * eased
            ),
            shouldApplySettings: true,
            isComplete: false
        )
    }

    private func smootherStep(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * clamped
            * (clamped * (clamped * 6 - 15) + 10)
    }

    private func interpolate(
        _ start: CGFloat,
        _ end: CGFloat,
        _ progress: CGFloat
    ) -> CGFloat {
        start + (end - start) * progress
    }
}

struct StatusPillMotion {
    /// Largest liquid width reached by any supported transition profile.
    nonisolated static let maximumWidthFactor: CGFloat = 18

    let fromX: CGFloat
    let toX: CGFloat
    let initialWidth: CGFloat
    let initialHeight: CGFloat
    let startTime: TimeInterval
    let duration: TimeInterval
    let sizeScale: CGFloat
    let itemWidth: CGFloat
    let style: IndicatorAnimationStyle

    init(
        fromX: CGFloat,
        toX: CGFloat,
        initialWidth: CGFloat = 12,
        initialHeight: CGFloat = 7,
        startTime: TimeInterval,
        sizeScale: CGFloat = 1,
        itemWidth: CGFloat = StatusItemArtwork.itemWidth,
        style: IndicatorAnimationStyle = .seamless
    ) {
        self.fromX = fromX
        self.toX = toX
        self.initialWidth = initialWidth
        self.initialHeight = initialHeight
        self.startTime = startTime
        self.sizeScale = sizeScale
        self.itemWidth = itemWidth
        self.style = style

        let distance = abs(toX - fromX)
        let crossedSpaces = max(distance / itemWidth, 1)
        switch style {
        case .seamless:
            // Give the shape enough time to be read as a morph instead of a
            // pill sliding between two points. Longer jumps receive a little
            // more travel time without ever becoming sluggish.
            duration = min(
                OrbitMotion.seamlessDuration
                    + min(TimeInterval(crossedSpaces - 1) * 0.02, 0.08),
                OrbitMotion.maximumFeedbackDuration
            )
        case .classic:
            duration = min(
                OrbitMotion.classicDuration
                    + min(TimeInterval(crossedSpaces - 1) * 0.015, 0.05),
                OrbitMotion.maximumFeedbackDuration
            )
        }
    }

    func frame(at timestamp: TimeInterval) -> StatusPillFrame {
        let rawProgress = CGFloat((timestamp - startTime) / duration)
        if rawProgress >= 0.999_999 {
            return .resting(at: toX, sizeScale: sizeScale)
        }
        if rawProgress <= 0 {
            return StatusPillFrame(
                x: fromX,
                width: initialWidth,
                height: initialHeight,
                progress: 0,
                isComplete: false
            )
        }

        let progress = min(max(rawProgress, 0), 1)
        let crossedSpaces = max(
            abs(toX - fromX) / itemWidth,
            1
        )
        switch style {
        case .seamless:
            return seamlessFrame(
                progress: progress,
                crossedSpaces: crossedSpaces
            )
        case .classic:
            return classicFrame(
                progress: progress,
                crossedSpaces: crossedSpaces
            )
        }
    }

    private func seamlessFrame(
        progress: CGFloat,
        crossedSpaces: CGFloat
    ) -> StatusPillFrame {
        let x = interpolate(fromX, toX, smootherStep(progress))
        let travellingWidth = (
            8.15 + min(crossedSpaces - 1, 4) * 0.25
        ) * sizeScale

        return StatusPillFrame(
            x: x,
            width: seamlessValue(
                progress: progress,
                values: [
                    initialWidth,
                    4.9 * sizeScale,
                    travellingWidth,
                    12.75 * sizeScale,
                    12 * sizeScale
                ]
            ),
            height: seamlessValue(
                progress: progress,
                values: [
                    initialHeight,
                    4.9 * sizeScale,
                    4.55 * sizeScale,
                    7.35 * sizeScale,
                    7 * sizeScale
                ]
            ),
            progress: progress,
            isComplete: false
        )
    }

    private func classicFrame(
        progress: CGFloat,
        crossedSpaces: CGFloat
    ) -> StatusPillFrame {
        let stretchedWidth = (
            16.6 + min(crossedSpaces - 1, 4) * 0.35
        ) * sizeScale
        return StatusPillFrame(
            x: interpolate(fromX, toX, classicPositionProgress(progress)),
            width: classicValue(
                progress: progress,
                values: [
                    initialWidth,
                    stretchedWidth,
                    10.9 * sizeScale,
                    12 * sizeScale
                ]
            ),
            height: classicValue(
                progress: progress,
                values: [
                    initialHeight,
                    6.15 * sizeScale,
                    7.35 * sizeScale,
                    7 * sizeScale
                ]
            ),
            progress: progress,
            isComplete: false
        )
    }

    private func seamlessValue(
        progress: CGFloat,
        values: [CGFloat]
    ) -> CGFloat {
        let keyTimes: [CGFloat] = [0, 0.18, 0.54, 0.82, 1]
        precondition(values.count == keyTimes.count)

        let phase = keyTimes.indices.dropLast().first {
            progress < keyTimes[$0 + 1]
        } ?? keyTimes.count - 2
        let phaseDuration = keyTimes[phase + 1] - keyTimes[phase]
        let localProgress = min(
            max((progress - keyTimes[phase]) / phaseDuration, 0),
            1
        )
        let startSlope = tangent(
            at: phase,
            keyTimes: keyTimes,
            values: values
        )
        let endSlope = tangent(
            at: phase + 1,
            keyTimes: keyTimes,
            values: values
        )

        // Cubic Hermite interpolation shares the exact same tangent on both
        // sides of every keyframe. Unlike easing each phase independently,
        // it never stops at the dot, droplet or overshoot checkpoints.
        let squared = localProgress * localProgress
        let cubed = squared * localProgress
        let startWeight = 2 * cubed - 3 * squared + 1
        let startTangentWeight = cubed - 2 * squared + localProgress
        let endWeight = -2 * cubed + 3 * squared
        let endTangentWeight = cubed - squared
        return startWeight * values[phase]
            + startTangentWeight * phaseDuration * startSlope
            + endWeight * values[phase + 1]
            + endTangentWeight * phaseDuration * endSlope
    }

    private func tangent(
        at index: Int,
        keyTimes: [CGFloat],
        values: [CGFloat]
    ) -> CGFloat {
        guard index > 0, index < values.count - 1 else { return 0 }

        let previousDuration = keyTimes[index] - keyTimes[index - 1]
        let nextDuration = keyTimes[index + 1] - keyTimes[index]
        let previousSlope = (values[index] - values[index - 1])
            / previousDuration
        let nextSlope = (values[index + 1] - values[index])
            / nextDuration

        // A real extremum should settle for one instant; points that continue
        // in the same direction keep a monotone, non-zero tangent.
        guard previousSlope * nextSlope > 0 else { return 0 }
        let previousWeight = 2 * nextDuration + previousDuration
        let nextWeight = nextDuration + 2 * previousDuration
        return (previousWeight + nextWeight)
            / (previousWeight / previousSlope + nextWeight / nextSlope)
    }

    private func classicValue(
        progress: CGFloat,
        values: [CGFloat]
    ) -> CGFloat {
        let keyTimes: [CGFloat] = [0, 0.34, 0.72, 1]
        let phase = progress < keyTimes[1]
            ? 0
            : progress < keyTimes[2] ? 1 : 2
        let local = (progress - keyTimes[phase])
            / (keyTimes[phase + 1] - keyTimes[phase])
        let clamped = min(max(local, 0), 1)
        return interpolate(
            values[phase],
            values[phase + 1],
            clamped * clamped * (3 - 2 * clamped)
        )
    }

    private func classicPositionProgress(_ progress: CGFloat) -> CGFloat {
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

    private func cubic(
        _ value: CGFloat,
        _ first: CGFloat,
        _ second: CGFloat
    ) -> CGFloat {
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

    private func smootherStep(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * clamped
            * (clamped * (clamped * 6 - 15) + 10)
    }

    private func interpolate(
        _ start: CGFloat,
        _ end: CGFloat,
        _ progress: CGFloat
    ) -> CGFloat {
        start + (end - start) * progress
    }
}

struct StatusHoverFrame: Equatable, Sendable {
    let scale: CGSize
    let isComplete: Bool
}

/// Display-link driven hover morph shared by regular and full-screen indicators.
/// It keeps the stable status-item bitmap while matching the liquid sizes and
/// the 0.30-second hover exit used by the previous layer-based implementation.
struct StatusHoverMotion {
    /// Largest horizontal overshoot used by the active hover morph.
    nonisolated static let maximumHorizontalScale: CGFloat = 1.42

    let index: Int
    let fromScale: CGSize
    let targetScale: CGSize
    let peakScale: CGSize
    let startTime: TimeInterval
    let duration: TimeInterval
    let peakTime: CGFloat

    init(
        index: Int,
        fromScale: CGSize,
        isHovered: Bool,
        isActive: Bool,
        startTime: TimeInterval
    ) {
        self.index = index
        self.fromScale = fromScale
        self.startTime = startTime

        if isHovered {
            duration = OrbitMotion.hoverEnterDuration
            peakTime = 0.68
            if isActive {
                targetScale = CGSize(width: 1.38, height: 1.25)
                peakScale = CGSize(
                    width: Self.maximumHorizontalScale,
                    height: 1.22
                )
            } else {
                targetScale = CGSize(
                    width: 11.75 / StatusItemArtwork.dotDiameter,
                    height: 7.75 / StatusItemArtwork.dotDiameter
                )
                peakScale = CGSize(
                    width: 12.3 / StatusItemArtwork.dotDiameter,
                    height: 7.6 / StatusItemArtwork.dotDiameter
                )
            }
        } else {
            duration = OrbitMotion.hoverExitDuration
            peakTime = 0.86
            targetScale = CGSize(width: 1, height: 1)
            if isActive {
                peakScale = CGSize(width: 0.99, height: 1.02)
            } else {
                peakScale = CGSize(
                    width: 4.35 / StatusItemArtwork.dotDiameter,
                    height: 4.65 / StatusItemArtwork.dotDiameter
                )
            }
        }
    }

    func frame(at timestamp: TimeInterval) -> StatusHoverFrame {
        let rawProgress = CGFloat((timestamp - startTime) / duration)
        guard rawProgress < 1 else {
            return StatusHoverFrame(scale: targetScale, isComplete: true)
        }
        guard rawProgress > 0 else {
            return StatusHoverFrame(scale: fromScale, isComplete: false)
        }

        let progress = min(max(rawProgress, 0), 1)
        let scale: CGSize
        if progress < peakTime {
            let localProgress = smoothStep(progress / peakTime)
            scale = interpolate(fromScale, peakScale, localProgress)
        } else {
            let localProgress = smoothStep(
                (progress - peakTime) / (1 - peakTime)
            )
            scale = interpolate(peakScale, targetScale, localProgress)
        }
        return StatusHoverFrame(scale: scale, isComplete: false)
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func interpolate(
        _ start: CGSize,
        _ end: CGSize,
        _ progress: CGFloat
    ) -> CGSize {
        CGSize(
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }
}
