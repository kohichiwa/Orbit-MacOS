import AppKit
import SwiftUI
import XCTest
@testable import Orbit

@MainActor
final class SystemSpacesReaderTests: XCTestCase {
    func testDecodesMainDisplayInMissionControlOrder() {
        let configuration: [String: Any] = [
            "Management Data": [
                "Monitors": [
                    [
                        "Display Identifier": "Secondary",
                        "Current Space": ["ManagedSpaceID": NSNumber(value: 9)],
                        "Spaces": [["ManagedSpaceID": NSNumber(value: 9), "type": 0]]
                    ],
                    [
                        "Display Identifier": "Main",
                        "Current Space": ["ManagedSpaceID": NSNumber(value: 22)],
                        "Spaces": [
                            ["ManagedSpaceID": NSNumber(value: 11), "type": 0],
                            ["ManagedSpaceID": NSNumber(value: 22), "type": 0],
                            ["ManagedSpaceID": NSNumber(value: 33), "type": 0]
                        ]
                    ]
                ]
            ]
        ]

        let snapshot = SystemSpacesReader.decode(configuration: configuration)
        XCTAssertEqual(snapshot?.orderedIdentifiers, [11, 22, 33])
        XCTAssertEqual(snapshot?.desktopIdentifiers, [11, 22, 33])
        XCTAssertEqual(snapshot?.activeIdentifier, 22)
        XCTAssertEqual(snapshot?.activeIndex, 1)
    }

    func testKeepsFullscreenSpacesInIndicatorOrder() {
        let configuration: [String: Any] = [
            "Management Data": [
                "Monitors": [[
                    "Display Identifier": "Main",
                    "Current Space": ["ManagedSpaceID": NSNumber(value: 30)],
                    "Spaces": [
                        ["ManagedSpaceID": NSNumber(value: 10), "type": 0],
                        ["ManagedSpaceID": NSNumber(value: 20), "type": 4],
                        ["ManagedSpaceID": NSNumber(value: 30), "type": 0]
                    ]
                ]]
            ]
        ]

        let snapshot = SystemSpacesReader.decode(configuration: configuration)
        XCTAssertEqual(snapshot?.orderedIdentifiers, [10, 20, 30])
        XCTAssertEqual(snapshot?.desktopIdentifiers, [10, 30])
        XCTAssertEqual(
            snapshot?.indicatorKinds,
            [
                .desktop(colorIndex: 0),
                .fullscreen(colorIndex: 0),
                .desktop(colorIndex: 1)
            ]
        )
        XCTAssertEqual(snapshot?.count, 3)
        XCTAssertEqual(snapshot?.activeIndex, 2)
        XCTAssertEqual(snapshot?.direction(toward: 10), .previous)
    }

    func testInvalidConfigurationReturnsNil() {
        XCTAssertNil(SystemSpacesReader.decode(configuration: ["invalid": true]))
    }

    func testReadsLiveSystemSnapshotWhenAvailable() async throws {
        let reader = SystemSpacesReader()
        guard let snapshot = await reader.read() else {
            throw XCTSkip("The host does not expose a Spaces configuration")
        }
        XCTAssertFalse(snapshot.orderedIdentifiers.isEmpty)
        XCTAssertFalse(snapshot.desktopIdentifiers.isEmpty)
        if let activeIdentifier = snapshot.activeIdentifier {
            XCTAssertTrue(snapshot.orderedIdentifiers.contains(activeIdentifier))
        }
    }

    func testForwardsActiveSpaceNotificationWithoutSender() async {
        let reader = SystemSpacesReader()
        let received = expectation(description: "Active Space change forwarded")
        reader.start { received.fulfill() }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        await fulfillment(of: [received], timeout: 1)
        reader.stop()
    }
}

final class SpaceViewModelTests: XCTestCase {
    @MainActor
    func testClickedDesktopIsSelectedThroughEveryIntermediateSpace() async {
        let initial = SpaceSnapshot(
            orderedIdentifiers: [10, 20, 30],
            desktopIdentifiers: [10, 30],
            activeIdentifier: 10
        )
        let fullscreen = SpaceSnapshot(
            orderedIdentifiers: [10, 20, 30],
            desktopIdentifiers: [10, 30],
            activeIdentifier: 20
        )
        let target = SpaceSnapshot(
            orderedIdentifiers: [10, 20, 30],
            desktopIdentifiers: [10, 30],
            activeIdentifier: 30
        )
        let reader = FakeSpacesReader(snapshots: [initial, fullscreen, target])
        let controller = FakeSpaceController(canPostEvents: true)
        let viewModel = SpaceViewModel(
            reader: reader,
            controller: controller,
            previewSnapshot: initial
        )

        await viewModel.select(2)

        XCTAssertEqual(viewModel.spaceCount, 3)
        XCTAssertEqual(viewModel.activeIndex, 2)
        XCTAssertEqual(controller.moves, [.next, .next])
        XCTAssertNil(viewModel.message)
    }

    @MainActor
    func testNewFullscreenSpaceRetainsItsSourceDesktopColor() async {
        let initial = SpaceSnapshot(identifiers: [10, 20], activeIndex: 1)
        let fullscreen = SpaceSnapshot(
            orderedIdentifiers: [10, 30, 20],
            desktopIdentifiers: [10, 20],
            activeIdentifier: 30,
            indicatorKinds: [
                .desktop(colorIndex: 0),
                .fullscreen(colorIndex: 0),
                .desktop(colorIndex: 1)
            ]
        )
        let viewModel = SpaceViewModel(
            reader: FakeSpacesReader(snapshots: [fullscreen]),
            controller: FakeSpaceController(canPostEvents: true),
            previewSnapshot: initial
        )

        await viewModel.refresh()

        XCTAssertEqual(
            viewModel.indicatorKinds,
            [
                .desktop(colorIndex: 0),
                .fullscreen(colorIndex: 1),
                .desktop(colorIndex: 1)
            ]
        )
        XCTAssertEqual(viewModel.activeIndex, 1)
    }

    @MainActor
    func testDotClickNeverRequestsPermissionAutomatically() async {
        let initial = SpaceSnapshot(identifiers: [1, 2, 3], activeIndex: 0)
        let reader = FakeSpacesReader(snapshots: [initial])
        let controller = FakeSpaceController(canPostEvents: false)
        let viewModel = SpaceViewModel(
            reader: reader,
            controller: controller,
            previewSnapshot: initial
        )

        await viewModel.select(2)

        XCTAssertEqual(viewModel.activeIndex, 0)
        XCTAssertTrue(controller.moves.isEmpty)
        XCTAssertEqual(controller.permissionRequestCount, 0)
        XCTAssertNotNil(viewModel.message)
    }

    @MainActor
    func testDotSelectionIsOptimisticWhileSystemSwitches() async {
        let initial = SpaceSnapshot(identifiers: [1, 2], activeIndex: 0)
        let target = SpaceSnapshot(identifiers: [1, 2], activeIndex: 1)
        let reader = PausingSpacesReader(initial: initial, target: target)
        let controller = FakeSpaceController(canPostEvents: true)
        let viewModel = SpaceViewModel(
            reader: reader,
            controller: controller,
            previewSnapshot: initial
        )

        let selection = Task { await viewModel.select(1) }
        await Task.yield()
        XCTAssertEqual(viewModel.activeIndex, 1)
        reader.allowChange()
        await selection.value
        XCTAssertEqual(viewModel.activeIndex, 1)
    }

    @MainActor
    func testExternalSpaceChangeUpdatesActiveDot() async throws {
        let initial = SpaceSnapshot(identifiers: [1, 2, 3], activeIndex: 0)
        let target = SpaceSnapshot(identifiers: [1, 2, 3], activeIndex: 2)
        let reader = EventSpacesReader(snapshot: initial)
        let viewModel = SpaceViewModel(
            reader: reader,
            controller: FakeSpaceController(canPostEvents: true),
            previewSnapshot: initial
        )

        viewModel.start()
        await viewModel.refresh()
        reader.snapshot = target
        reader.sendChange()

        for _ in 0..<20 where viewModel.activeIndex != 2 {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(viewModel.activeIndex, 2)
        viewModel.stop()
    }

    @MainActor
    func testTransientSnapshotWithoutCurrentSpaceDoesNotHideActivePill() async {
        let initial = SpaceSnapshot(identifiers: [1, 2, 3], activeIndex: 0)
        let transient = SpaceSnapshot(
            orderedIdentifiers: [1, 2, 3],
            desktopIdentifiers: [1, 2, 3],
            activeIdentifier: nil
        )
        let target = SpaceSnapshot(identifiers: [1, 2, 3], activeIndex: 1)
        let reader = EventSpacesReader(snapshot: initial)
        let viewModel = SpaceViewModel(
            reader: reader,
            controller: FakeSpaceController(canPostEvents: true),
            previewSnapshot: initial
        )

        await viewModel.refresh()
        reader.snapshot = transient
        await viewModel.refresh()
        XCTAssertEqual(viewModel.activeIndex, 0)

        reader.snapshot = target
        await viewModel.refresh()

        XCTAssertEqual(viewModel.activeIndex, 1)
    }

    @MainActor
    func testStatusItemWidthAndLightDarkRendering() throws {
        XCTAssertEqual(StatusItemView.preferredWidth(for: 1), 22)
        XCTAssertEqual(StatusItemView.preferredWidth(for: 4), 64)
        try renderStatusItem(appearance: .aqua, filename: "OrbitMinimal-light.png")
        try renderStatusItem(appearance: .darkAqua, filename: "OrbitMinimal-dark.png")
    }

    @MainActor
    func testStatusItemGeometrySupportsArbitrarySpaceCount() {
        for count in [1, 2, 3, 4, 10, 32] {
            let width = StatusItemArtwork.preferredWidth(for: count)
            let firstCenter = StatusItemArtwork.centerX(for: 0)
            let lastCenter = StatusItemArtwork.centerX(for: count - 1)

            XCTAssertGreaterThan(firstCenter, 0)
            XCTAssertLessThan(lastCenter, width)
            XCTAssertEqual(
                lastCenter - firstCenter,
                CGFloat(count - 1) * StatusItemArtwork.itemWidth
            )
        }
    }

    @MainActor
    func testCrowdedStatusItemScalesToItsWidthBudget() {
        let regularScale = StatusItemArtwork.fittedSizeScale(
            for: 4,
            requestedSizeScale: 1.3,
            spacingScale: 1
        )
        XCTAssertEqual(regularScale, 1.3, accuracy: 0.0001)

        for count in [13, 16, 32] {
            let fittedScale = StatusItemArtwork.fittedSizeScale(
                for: count,
                requestedSizeScale: 1.7,
                spacingScale: 1 + 8.0 / 12
            )
            let fittedWidth = StatusItemArtwork.preferredWidth(
                for: count,
                sizeScale: fittedScale,
                spacingScale: 1 + 8.0 / 12
            )

            XCTAssertGreaterThan(fittedScale, 0)
            XCTAssertLessThan(fittedScale, 1.7)
            XCTAssertLessThanOrEqual(
                fittedWidth,
                StatusItemArtwork.maximumStatusItemWidth + 0.001
            )
        }
    }

    func testPopupDismissalOnlyAcceptsClicksOutsideProtectedContent() {
        let protectedRects = [
            CGRect(x: 20, y: 30, width: 100, height: 40),
            CGRect(x: 180, y: 20, width: 24, height: 24)
        ]

        XCTAssertFalse(PopupDismissalPolicy.shouldDismiss(
            clickPoint: CGPoint(x: 60, y: 50),
            protectedRects: protectedRects
        ))
        XCTAssertFalse(PopupDismissalPolicy.shouldDismiss(
            clickPoint: CGPoint(x: 17, y: 50),
            protectedRects: protectedRects
        ))
        XCTAssertTrue(PopupDismissalPolicy.shouldDismiss(
            clickPoint: CGPoint(x: 150, y: 90),
            protectedRects: protectedRects
        ))
    }

    func testDemoSwipeRegionExtendsThroughBackgroundTransition() {
        let demoBounds = CGRect(x: 0, y: 0, width: 540, height: 218)
        let transitionExtension: CGFloat = 72

        XCTAssertTrue(DemoSwipeRegionPolicy.contains(
            CGPoint(x: 270, y: 217),
            in: demoBounds,
            bottomExtension: transitionExtension
        ))
        XCTAssertTrue(DemoSwipeRegionPolicy.contains(
            CGPoint(x: 270, y: 289),
            in: demoBounds,
            bottomExtension: transitionExtension
        ))
        XCTAssertFalse(DemoSwipeRegionPolicy.contains(
            CGPoint(x: 270, y: 291),
            in: demoBounds,
            bottomExtension: transitionExtension
        ))
        XCTAssertFalse(DemoSwipeRegionPolicy.contains(
            CGPoint(x: 541, y: 250),
            in: demoBounds,
            bottomExtension: transitionExtension
        ))
    }

    @MainActor
    func testPillMotionIsSymmetricBetweenEdgeAndCenter() {
        let center = StatusItemArtwork.centerX(for: 1)
        let edge = StatusItemArtwork.centerX(for: 2)
        let outward = StatusPillMotion(
            fromX: center,
            toX: edge,
            startTime: 10
        )
        let inward = StatusPillMotion(
            fromX: edge,
            toX: center,
            startTime: 10
        )
        let progressTime = 10 + outward.duration * 0.52
        let outwardFrame = outward.frame(at: progressTime)
        let inwardFrame = inward.frame(at: progressTime)

        XCTAssertEqual(outwardFrame.width, inwardFrame.width, accuracy: 0.0001)
        XCTAssertEqual(outwardFrame.height, inwardFrame.height, accuracy: 0.0001)
        XCTAssertEqual(outwardFrame.x + inwardFrame.x, center + edge, accuracy: 0.0001)
    }

    @MainActor
    func testPillMotionClearlyMorphsThroughDotAndLiquidOvershoot() {
        let source = StatusItemArtwork.centerX(for: 0)
        let target = StatusItemArtwork.centerX(for: 1)
        let motion = StatusPillMotion(
            fromX: source,
            toX: target,
            startTime: 4
        )

        let collapsed = motion.frame(
            at: 4 + motion.duration * 0.18
        )
        XCTAssertEqual(collapsed.width, collapsed.height, accuracy: 0.001)
        XCTAssertLessThan(collapsed.width, StatusItemArtwork.dotDiameter * 1.1)

        let travelling = motion.frame(
            at: 4 + motion.duration * 0.54
        )
        XCTAssertGreaterThan(travelling.width, travelling.height)
        XCTAssertGreaterThan(travelling.x, source)
        XCTAssertLessThan(travelling.x, target)

        let arriving = motion.frame(
            at: 4 + motion.duration * 0.82
        )
        XCTAssertGreaterThan(arriving.x, source)
        XCTAssertLessThan(arriving.x, target)
        XCTAssertGreaterThan(arriving.width, 12)
        XCTAssertGreaterThan(arriving.height, 7)

        let settled = motion.frame(at: 4 + motion.duration)
        XCTAssertTrue(settled.isComplete)
        XCTAssertEqual(settled, .resting(at: target))
    }

    @MainActor
    func testPillMotionHasNoInternalPositionPlateaus() {
        let source = StatusItemArtwork.centerX(for: 0)
        let target = StatusItemArtwork.centerX(for: 3)
        let motion = StatusPillMotion(
            fromX: source,
            toX: target,
            startTime: 8
        )
        let positions = (1..<20).map { sample in
            motion.frame(
                at: 8 + motion.duration * Double(sample) / 20
            ).x
        }

        for (previous, next) in zip(positions, positions.dropFirst()) {
            XCTAssertGreaterThan(next, previous)
        }
    }

    @MainActor
    func testClassicPillMotionUsesBriefSnappyProfile() {
        let source = StatusItemArtwork.centerX(for: 0)
        let target = StatusItemArtwork.centerX(for: 1)
        let motion = StatusPillMotion(
            fromX: source,
            toX: target,
            startTime: 12,
            style: .classic
        )

        XCTAssertEqual(
            motion.duration,
            OrbitMotion.classicDuration,
            accuracy: 0.0001
        )
        let stretched = motion.frame(
            at: 12 + motion.duration * 0.34
        )
        XCTAssertEqual(stretched.width, 16.6, accuracy: 0.001)
        XCTAssertEqual(stretched.height, 6.15, accuracy: 0.001)
        XCTAssertGreaterThan(stretched.x, source)
        XCTAssertLessThan(stretched.x, target)

        let settled = motion.frame(at: 12 + motion.duration)
        XCTAssertEqual(settled, .resting(at: target))
    }

    @MainActor
    func testContinuousPillBridgesSourceAndDestinationWithoutAGap() {
        let source = StatusItemArtwork.centerX(for: 0)
        let target = StatusItemArtwork.centerX(for: 3)
        let startTime: TimeInterval = 16
        let forward = StatusPillMotion(
            fromX: source,
            toX: target,
            startTime: startTime,
            style: .continuous
        )
        let backward = StatusPillMotion(
            fromX: target,
            toX: source,
            startTime: startTime,
            style: .continuous
        )

        let forwardBridge = forward.frame(
            at: startTime + forward.duration * 0.62
        )
        let backwardBridge = backward.frame(
            at: startTime + backward.duration * 0.62
        )
        let forwardLeft = forwardBridge.x - forwardBridge.width / 2
        let forwardRight = forwardBridge.x + forwardBridge.width / 2

        XCTAssertLessThanOrEqual(forwardLeft, source)
        XCTAssertGreaterThanOrEqual(forwardRight, target)
        XCTAssertGreaterThan(forwardBridge.width, target - source)
        XCTAssertGreaterThan(forwardBridge.waist, 0.7)
        XCTAssertEqual(
            forwardBridge.width,
            backwardBridge.width,
            accuracy: 0.001
        )
        XCTAssertEqual(
            forwardBridge.waist,
            backwardBridge.waist,
            accuracy: 0.001
        )
        XCTAssertEqual(
            forwardBridge.x + backwardBridge.x,
            source + target,
            accuracy: 0.001
        )

        XCTAssertEqual(
            forward.frame(at: startTime + forward.duration),
            .resting(at: target)
        )
        XCTAssertEqual(forward.frame(at: startTime).waist, 0)
        XCTAssertEqual(
            forward.frame(at: startTime + forward.duration).waist,
            0
        )
    }

    @MainActor
    func testPillFeedbackMotionAlwaysStaysBrief() {
        for style in IndicatorAnimationStyle.allCases {
            let motion = StatusPillMotion(
                fromX: StatusItemArtwork.centerX(for: 0),
                toX: StatusItemArtwork.centerX(for: 99),
                startTime: 0,
                style: style
            )

            XCTAssertLessThanOrEqual(
                motion.duration,
                OrbitMotion.maximumFeedbackDuration
            )
        }
    }

    @MainActor
    func testArtworkRefreshAppliesChangesOnlyWhileFullyHidden() {
        let motion = StatusArtworkRefreshMotion(
            startTime: 20,
            initialPresentation: .identity
        )

        let start = motion.frame(at: 20)
        XCTAssertEqual(start.presentation, .identity)
        XCTAssertFalse(start.shouldApplySettings)

        let hidden = motion.frame(
            at: 20 + IndicatorRefreshTiming.disappearDuration
        )
        XCTAssertEqual(hidden.presentation.opacity, 0, accuracy: 0.001)
        XCTAssertLessThan(hidden.presentation.scaleX, 1)
        XCTAssertLessThan(hidden.presentation.scaleY, hidden.presentation.scaleX)
        XCTAssertTrue(hidden.shouldApplySettings)

        let returning = motion.frame(
            at: 20 + IndicatorRefreshTiming.disappearDuration
                + IndicatorRefreshTiming.appearDuration * 0.75
        )
        XCTAssertGreaterThan(returning.presentation.opacity, 0.8)
        XCTAssertGreaterThan(returning.presentation.scaleX, 0.95)

        let finished = motion.frame(
            at: 20 + IndicatorRefreshTiming.totalDuration
        )
        XCTAssertEqual(finished.presentation, .identity)
        XCTAssertTrue(finished.shouldApplySettings)
        XCTAssertTrue(finished.isComplete)
    }

    @MainActor
    func testHoverMotionUsesLiquidEntryAndThirtyHundredthsExit() {
        let resting = CGSize(width: 1, height: 1)
        let entry = StatusHoverMotion(
            index: 1,
            fromScale: resting,
            isHovered: true,
            isActive: false,
            startTime: 10
        )
        XCTAssertEqual(entry.duration, 0.22, accuracy: 0.001)
        XCTAssertEqual(entry.targetScale.width, 11.75 / 4.5, accuracy: 0.001)
        XCTAssertEqual(entry.targetScale.height, 7.75 / 4.5, accuracy: 0.001)

        let peak = entry.frame(at: 10 + entry.duration * entry.peakTime)
        XCTAssertGreaterThan(peak.scale.width, entry.targetScale.width)
        XCTAssertLessThan(peak.scale.height, entry.targetScale.height)

        let exit = StatusHoverMotion(
            index: 1,
            fromScale: entry.targetScale,
            isHovered: false,
            isActive: false,
            startTime: 20
        )
        XCTAssertEqual(exit.duration, 0.30, accuracy: 0.001)
        let finished = exit.frame(at: 20 + exit.duration)
        XCTAssertTrue(finished.isComplete)
        XCTAssertEqual(finished.scale, resting)

        let activeEntry = StatusHoverMotion(
            index: 0,
            fromScale: resting,
            isHovered: true,
            isActive: true,
            startTime: 30
        )
        XCTAssertEqual(activeEntry.targetScale.width, 1.38, accuracy: 0.001)
        XCTAssertEqual(activeEntry.targetScale.height, 1.25, accuracy: 0.001)
    }

    @MainActor
    func testAnimatedArtworkKeepsOneAppearanceIndependentImageInstance() {
        let renderer = StatusIndicatorImageRenderer(count: 6)
        let installedImage = renderer.image

        renderer.update(
            pill: .resting(at: StatusItemArtwork.centerX(for: 0))
        )
        let firstFrame = installedImage.tiffRepresentation
        renderer.update(
            pill: .resting(at: StatusItemArtwork.centerX(for: 5))
        )
        let lastFrame = installedImage.tiffRepresentation

        XCTAssertTrue(installedImage === renderer.image)
        XCTAssertFalse(installedImage.isTemplate)
        XCTAssertEqual(installedImage.size, NSSize(width: 84, height: 22))
        XCTAssertNotEqual(firstFrame, lastFrame)

        guard
            let firstFrame,
            let lastFrame,
            let firstBitmap = NSBitmapImageRep(data: firstFrame),
            let lastBitmap = NSBitmapImageRep(data: lastFrame),
            let firstPillBounds = opaquePixelBounds(in: firstBitmap),
            let lastPillBounds = opaquePixelBounds(in: lastBitmap)
        else {
            return XCTFail("Could not inspect rendered status item frames")
        }

        XCTAssertEqual(firstBitmap.pixelsWide, 168)
        XCTAssertEqual(firstBitmap.pixelsHigh, 44)
        XCTAssertLessThan(firstPillBounds.maxX, 35)
        XCTAssertGreaterThan(lastPillBounds.minX, 135)
        XCTAssertLessThan(lastPillBounds.maxX, 168)
        XCTAssertEqual(firstPillBounds.width, lastPillBounds.width, accuracy: 1)
        XCTAssertEqual(firstPillBounds.height, lastPillBounds.height, accuracy: 1)
        XCTAssertEqual(firstPillBounds.width, 24, accuracy: 3)
        XCTAssertEqual(firstPillBounds.height, 14, accuracy: 3)
    }

    @MainActor
    func testHoverMorphEnlargesTheIndicatorItself() throws {
        let renderer = StatusIndicatorImageRenderer(count: 1)
        guard
            let restingData = renderer.image.tiffRepresentation,
            let restingBitmap = NSBitmapImageRep(data: restingData),
            let restingBounds = opaquePixelBounds(
                in: restingBitmap,
                minimumAlpha: 0.1
            )
        else {
            return XCTFail("Could not inspect resting indicator")
        }

        let hover = StatusHoverMotion(
            index: 0,
            fromScale: CGSize(width: 1, height: 1),
            isHovered: true,
            isActive: false,
            startTime: 0
        )
        renderer.update(
            pill: nil,
            hoverScales: [0: hover.targetScale]
        )

        guard
            let hoveredData = renderer.image.tiffRepresentation,
            let hoveredBitmap = NSBitmapImageRep(data: hoveredData),
            let hoveredBounds = opaquePixelBounds(
                in: hoveredBitmap,
                minimumAlpha: 0.1
            )
        else {
            return XCTFail("Could not inspect hovered indicator")
        }

        XCTAssertGreaterThan(hoveredBounds.width, restingBounds.width * 2)
        XCTAssertGreaterThan(hoveredBounds.height, restingBounds.height)
        XCTAssertEqual(renderer.hoverScales[0], hover.targetScale)
    }

    @MainActor
    func testPreviewPaddingContainsEveryEdgeTransitionFrame() throws {
        let count = 6
        let sizeScale: CGFloat = 3
        let spacingScale: CGFloat = 1
        let overflowPadding = SyncedIndicatorArtworkView
            .horizontalOverflowPadding(
                for: sizeScale,
                spacingScale: spacingScale
            )
        let renderer = StatusIndicatorImageRenderer(
            count: count,
            sizeScale: sizeScale,
            spacingScale: spacingScale,
            imageHeight: 45,
            horizontalOverflowPadding: overflowPadding
        )
        let inactiveHover = StatusHoverMotion(
            index: count - 1,
            fromScale: CGSize(width: 1, height: 1),
            isHovered: true,
            isActive: false,
            startTime: 0
        )

        for (sourceIndex, targetIndex) in [(0, count - 1), (count - 1, 0)] {
            let activeHover = StatusHoverMotion(
                index: targetIndex,
                fromScale: inactiveHover.targetScale,
                isHovered: true,
                isActive: true,
                startTime: 0
            )
            let motion = StatusPillMotion(
                fromX: StatusItemArtwork.centerX(
                    for: sourceIndex,
                    sizeScale: sizeScale,
                    spacingScale: spacingScale
                ),
                toX: StatusItemArtwork.centerX(
                    for: targetIndex,
                    sizeScale: sizeScale,
                    spacingScale: spacingScale
                ),
                startTime: 0,
                sizeScale: sizeScale,
                itemWidth: StatusItemArtwork.itemWidth(
                    sizeScale: sizeScale,
                    spacingScale: spacingScale
                ),
                style: .classic
            )

            for step in 0...120 {
                let timestamp = motion.duration * Double(step) / 120
                renderer.update(
                    pill: motion.frame(at: timestamp),
                    activeIndex: targetIndex,
                    hoverScales: [
                        targetIndex: activeHover.frame(at: timestamp).scale
                    ]
                )
                guard
                    let data = renderer.image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: data),
                    let bounds = opaquePixelBounds(
                        in: bitmap,
                        minimumAlpha: 0.01
                    )
                else {
                    return XCTFail("Could not inspect transition frame")
                }
                XCTAssertGreaterThan(bounds.minX, 0)
                XCTAssertLessThan(
                    bounds.maxX,
                    CGFloat(bitmap.pixelsWide)
                )
            }
        }
    }

    @MainActor
    func testThinOutlineChangesDesktopAndFullscreenIndicators() throws {
        let plainDesktop = StatusIndicatorImageRenderer(
            count: 1,
            indicatorColors: [.systemBlue]
        )
        let outlinedDesktop = StatusIndicatorImageRenderer(
            count: 1,
            indicatorColors: [.systemBlue],
            showsThinOutline: true
        )

        XCTAssertNotEqual(
            plainDesktop.image.tiffRepresentation,
            outlinedDesktop.image.tiffRepresentation
        )

        let fullscreenKinds: [SpaceIndicatorKind] = [
            .fullscreen(colorIndex: 0)
        ]
        let plainFullscreen = StatusIndicatorImageRenderer(
            count: 1,
            indicatorKinds: fullscreenKinds,
            indicatorColors: [.systemBlue]
        )
        let outlinedFullscreen = StatusIndicatorImageRenderer(
            count: 1,
            indicatorKinds: fullscreenKinds,
            indicatorColors: [.systemBlue],
            showsThinOutline: true
        )

        XCTAssertNotEqual(
            plainFullscreen.image.tiffRepresentation,
            outlinedFullscreen.image.tiffRepresentation
        )
    }

    @MainActor
    func testShapeStyleChangesDesktopAndFullscreenSilhouettes() {
        let sizeScale: CGFloat = 1.7
        let indicatorKinds: [SpaceIndicatorKind] = [
            .desktop(colorIndex: 0),
            .fullscreen(colorIndex: 0)
        ]
        func image(for style: IndicatorShapeStyle) -> Data? {
            let renderer = StatusIndicatorImageRenderer(
                count: indicatorKinds.count,
                indicatorKinds: indicatorKinds,
                indicatorColors: [.systemBlue],
                shapeStyle: style,
                sizeScale: sizeScale
            )
            renderer.update(
                pill: .resting(
                    at: StatusItemArtwork.centerX(
                        for: 0,
                        sizeScale: sizeScale
                    ),
                    sizeScale: sizeScale,
                    shapeStyle: style
                ),
                activeIndex: 0
            )
            return renderer.image.tiffRepresentation
        }

        XCTAssertNotEqual(
            image(for: .standard),
            image(for: .circles)
        )
        XCTAssertNotEqual(
            image(for: .standard),
            image(for: .roundedRectangles)
        )
        XCTAssertNotEqual(
            image(for: .circles),
            image(for: .roundedRectangles)
        )

        let circle = StatusPillFrame.resting(
            at: 0,
            shapeStyle: .circles
        )
        XCTAssertEqual(circle.width, circle.height)
        XCTAssertGreaterThan(
            StatusPillFrame.resting(at: 0, shapeStyle: .standard).width,
            circle.width
        )

        let circleMotion = StatusPillMotion(
            fromX: 0,
            toX: StatusItemArtwork.itemWidth,
            startTime: 0,
            shapeStyle: .circles
        )
        XCTAssertEqual(
            circleMotion.frame(at: circleMotion.duration),
            .resting(
                at: StatusItemArtwork.itemWidth,
                shapeStyle: .circles
            )
        )
        let circleHover = StatusHoverMotion(
            index: 0,
            fromScale: CGSize(width: 1, height: 1),
            isHovered: true,
            isActive: true,
            startTime: 0,
            shapeStyle: .circles
        )
        XCTAssertEqual(
            circleHover.targetScale.width,
            circleHover.targetScale.height
        )
    }

    @MainActor
    func testFullscreenThinOutlineSurroundsColoredStroke() throws {
        let sizeScale: CGFloat = 1.7
        let renderer = StatusIndicatorImageRenderer(
            count: 1,
            indicatorKinds: [.fullscreen(colorIndex: 0)],
            indicatorColors: [.systemYellow],
            showsThinOutline: true,
            sizeScale: sizeScale
        )
        renderer.update(
            pill: .resting(
                at: StatusItemArtwork.centerX(
                    for: 0,
                    sizeScale: sizeScale
                ),
                sizeScale: sizeScale
            ),
            activeIndex: 0
        )

        let data = try XCTUnwrap(renderer.image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let centerX = bitmap.pixelsWide / 2
        let centerY = bitmap.pixelsHigh / 2
        let leftHalf = (0..<centerX).compactMap { x -> (Int, NSColor)? in
            guard let color = bitmap.colorAt(x: x, y: centerY) else {
                return nil
            }
            return (x, color)
        }
        let contrastPixels = leftHalf.filter { _, color in
            color.alphaComponent > 0.04
                && color.redComponent < 0.35
                && color.greenComponent < 0.35
                && color.blueComponent < 0.35
        }.map(\.0)
        let coloredPixels = leftHalf.filter { _, color in
            color.alphaComponent > 0.2
                && color.redComponent > 0.65
                && color.greenComponent > 0.45
        }.map(\.0)

        XCTAssertFalse(contrastPixels.isEmpty)
        XCTAssertFalse(coloredPixels.isEmpty)
        XCTAssertLessThan(
            try XCTUnwrap(contrastPixels.min()),
            try XCTUnwrap(coloredPixels.min())
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(contrastPixels.max()),
            try XCTUnwrap(coloredPixels.max())
        )
    }

    @MainActor
    func testFullscreenIndicatorUsesMatchingInnerOutline() throws {
        let renderer = StatusIndicatorImageRenderer(
            count: 3,
            indicatorKinds: [
                .desktop(colorIndex: 0),
                .fullscreen(colorIndex: 0),
                .desktop(colorIndex: 1)
            ],
            indicatorColors: [.systemRed, .systemBlue]
        )
        renderer.update(pill: nil)

        guard
            let data = renderer.image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: data)
        else {
            return XCTFail("Could not inspect full-screen indicator artwork")
        }

        let centerX = Int(
            (StatusItemArtwork.itemWidth * 1.5) * 2
        )
        let centerY = bitmap.pixelsHigh / 2
        XCTAssertLessThan(
            bitmap.colorAt(x: centerX, y: centerY)?.alphaComponent ?? 1,
            0.05
        )

        let outlineColors = (-6...6).flatMap { xOffset in
            (-6...6).compactMap { yOffset in
                bitmap.colorAt(
                    x: centerX + xOffset,
                    y: centerY + yOffset
                )
            }
        }.filter { $0.alphaComponent > 0.2 }
        XCTAssertFalse(outlineColors.isEmpty)
        XCTAssertGreaterThan(
            outlineColors.map(\.redComponent).max() ?? 0,
            outlineColors.map(\.blueComponent).max() ?? 1
        )

        renderer.update(
            pill: .resting(at: StatusItemArtwork.centerX(for: 1)),
            activeIndex: 1
        )
        guard
            let activeData = renderer.image.tiffRepresentation,
            let activeBitmap = NSBitmapImageRep(data: activeData)
        else {
            return XCTFail("Could not inspect active full-screen pill")
        }
        XCTAssertLessThan(
            activeBitmap.colorAt(x: centerX, y: centerY)?.alphaComponent ?? 1,
            0.05
        )
    }

    private func opaquePixelBounds(
        in bitmap: NSBitmapImageRep,
        minimumAlpha: CGFloat = 0.8
    ) -> NSRect? {
        var minimumX = bitmap.pixelsWide
        var minimumY = bitmap.pixelsHigh
        var maximumX = -1
        var maximumY = -1

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard
                    (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                        > minimumAlpha
                else {
                    continue
                }
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }

        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
        return NSRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX + 1,
            height: maximumY - minimumY + 1
        )
    }

    @MainActor
    private func renderStatusItem(appearance: NSAppearance.Name, filename: String) throws {
        let snapshot = SpaceSnapshot(identifiers: [1, 2, 3, 4], activeIndex: 1)
        let controller = FakeSpaceController(canPostEvents: true)
        let viewModel = SpaceViewModel(controller: controller, previewSnapshot: snapshot)
        let root = StatusItemView(viewModel: viewModel)
            .frame(width: StatusItemView.preferredWidth(for: snapshot.count), height: 22)
        let hostingView = NSHostingView(rootView: root)
        hostingView.appearance = NSAppearance(named: appearance)
        hostingView.frame = NSRect(x: 0, y: 0, width: StatusItemView.preferredWidth(for: snapshot.count), height: 22)
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return XCTFail("Could not create bitmap")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            return XCTFail("Could not encode PNG")
        }
        try data.write(to: URL(fileURLWithPath: "/tmp/\(filename)"), options: .atomic)
    }
}

@MainActor
private final class FakeSpacesReader: SpacesReading {
    private var snapshots: [SpaceSnapshot]

    init(snapshots: [SpaceSnapshot]) {
        self.snapshots = snapshots
    }

    func start(onChange: @escaping () -> Void) {}
    func stop() {}

    func read() async -> SpaceSnapshot? {
        guard !snapshots.isEmpty else { return nil }
        if snapshots.count == 1 { return snapshots[0] }
        return snapshots.removeFirst()
    }
}

@MainActor
private final class PausingSpacesReader: SpacesReading {
    private let initial: SpaceSnapshot
    private let target: SpaceSnapshot
    private var changeAllowed = false

    init(initial: SpaceSnapshot, target: SpaceSnapshot) {
        self.initial = initial
        self.target = target
    }

    func start(onChange: @escaping () -> Void) {}
    func stop() {}
    func allowChange() { changeAllowed = true }
    func read() async -> SpaceSnapshot? { changeAllowed ? target : initial }
}

@MainActor
private final class EventSpacesReader: SpacesReading {
    var snapshot: SpaceSnapshot
    private var changeHandler: (() -> Void)?

    init(snapshot: SpaceSnapshot) {
        self.snapshot = snapshot
    }

    func start(onChange: @escaping () -> Void) { changeHandler = onChange }
    func stop() { changeHandler = nil }
    func read() async -> SpaceSnapshot? { snapshot }
    func sendChange() { changeHandler?() }
}

@MainActor
private final class FakeSpaceController: SpaceControlling {
    let canPostEvents: Bool
    private(set) var moves: [SpaceDirection] = []
    private(set) var permissionRequestCount = 0

    init(canPostEvents: Bool) {
        self.canPostEvents = canPostEvents
    }

    func requestAccessibilityPermission() -> Bool {
        permissionRequestCount += 1
        return canPostEvents
    }

    func move(_ direction: SpaceDirection) async throws {
        moves.append(direction)
    }
}
