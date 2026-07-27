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
    func testOlderRefreshCannotOverwriteANewerSnapshot() async {
        let initial = SpaceSnapshot(identifiers: [1, 2, 3], activeIndex: 0)
        let stale = SpaceSnapshot(identifiers: [1, 2, 3], activeIndex: 1)
        let current = SpaceSnapshot(identifiers: [1, 2, 3], activeIndex: 2)
        let reader = ControlledSpacesReader()
        let viewModel = SpaceViewModel(
            reader: reader,
            controller: FakeSpaceController(canPostEvents: true),
            previewSnapshot: initial
        )

        let firstRefresh = Task { await viewModel.refresh() }
        await waitForPendingReads(1, in: reader)
        let firstRead = reader.pendingReadIdentifiers.first

        let secondRefresh = Task { await viewModel.refresh() }
        await waitForPendingReads(2, in: reader)
        let secondRead = reader.pendingReadIdentifiers.last

        guard let firstRead, let secondRead, firstRead != secondRead else {
            firstRefresh.cancel()
            secondRefresh.cancel()
            return XCTFail("Expected two independent pending reads")
        }

        reader.resume(read: secondRead, with: current)
        await secondRefresh.value
        XCTAssertEqual(viewModel.activeIndex, 2)

        reader.resume(read: firstRead, with: stale)
        await firstRefresh.value
        XCTAssertEqual(viewModel.activeIndex, 2)
    }

    @MainActor
    func testStoppingStatusBarControllerReleasesItsDisplayLinkTarget() async {
        let suiteName = "OrbitTests.status.stop.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let snapshot = SpaceSnapshot(identifiers: [1, 2, 3], activeIndex: 1)
        let viewModel = SpaceViewModel(
            controller: FakeSpaceController(canPostEvents: true),
            previewSnapshot: snapshot
        )
        var controller: StatusBarController? = StatusBarController(
            viewModel: viewModel,
            settings: settings
        )
        weak let releasedController = controller

        controller?.stop()
        controller = nil
        await Task.yield()

        XCTAssertNil(releasedController)
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

    func testStatusAccessibilityDistinguishesDesktopAndFullscreen() {
        let kinds: [SpaceIndicatorKind] = [
            .desktop(colorIndex: 0),
            .fullscreen(colorIndex: 0)
        ]
        let desktop = StatusAccessibility.value(
            for: 0,
            indicatorKinds: kinds
        )
        let fullscreen = StatusAccessibility.value(
            for: 1,
            indicatorKinds: kinds
        )

        XCTAssertTrue(
            desktop?.localizedCaseInsensitiveContains("desktop") == true
                || desktop?.localizedCaseInsensitiveContains("стол") == true
        )
        XCTAssertTrue(
            fullscreen?.localizedCaseInsensitiveContains("fullscreen") == true
                || fullscreen?.localizedCaseInsensitiveContains("полноэкран")
                    == true
        )
        XCTAssertNil(StatusAccessibility.value(for: 2, indicatorKinds: kinds))
        XCTAssertNil(
            StatusAccessibility.value(for: nil, indicatorKinds: kinds)
        )
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
    func testSpacingChangesOnlyInternalIndicatorGaps() {
        let count = 6
        let sizeScale: CGFloat = 1.4
        let compactSpacing: CGFloat = 1
        let expandedSpacing: CGFloat = 1.6

        let compactWidth = StatusItemArtwork.preferredWidth(
            for: count,
            sizeScale: sizeScale,
            spacingScale: compactSpacing
        )
        let expandedWidth = StatusItemArtwork.preferredWidth(
            for: count,
            sizeScale: sizeScale,
            spacingScale: expandedSpacing
        )
        let compactFirst = StatusItemArtwork.centerX(
            for: 0,
            sizeScale: sizeScale,
            spacingScale: compactSpacing
        )
        let expandedFirst = StatusItemArtwork.centerX(
            for: 0,
            sizeScale: sizeScale,
            spacingScale: expandedSpacing
        )
        let compactLast = StatusItemArtwork.centerX(
            for: count - 1,
            sizeScale: sizeScale,
            spacingScale: compactSpacing
        )
        let expandedLast = StatusItemArtwork.centerX(
            for: count - 1,
            sizeScale: sizeScale,
            spacingScale: expandedSpacing
        )

        XCTAssertEqual(compactFirst, expandedFirst, accuracy: 0.0001)
        XCTAssertEqual(
            compactWidth - compactLast,
            expandedWidth - expandedLast,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(
            expandedLast - expandedFirst,
            compactLast - compactFirst
        )
        XCTAssertEqual(
            StatusItemArtwork.preferredWidth(
                for: 1,
                sizeScale: sizeScale,
                spacingScale: compactSpacing
            ),
            StatusItemArtwork.preferredWidth(
                for: 1,
                sizeScale: sizeScale,
                spacingScale: expandedSpacing
            ),
            accuracy: 0.0001
        )
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

    @MainActor
    func testPopupPlacementKeepsBubbleInsideWindowAndPointerOnIndicator() {
        let containerWidth: CGFloat = 540
        let bubbleWidth: CGFloat = 238
        let interfaceInset: CGFloat = 24
        let pointerEdgeInset: CGFloat = 31
        let halfContainer = containerWidth / 2
        let halfBubble = bubbleWidth / 2
        let maximumPointerOffset = halfBubble - pointerEdgeInset

        for anchorOffset in [-242.0, 0, 242.0] {
            let placement = PopupHorizontalPlacement.resolve(
                anchorOffset: anchorOffset,
                containerWidth: containerWidth,
                bubbleWidth: bubbleWidth,
                horizontalInset: interfaceInset,
                pointerEdgeInset: pointerEdgeInset
            )

            XCTAssertGreaterThanOrEqual(
                placement.bubbleCenterOffset - halfBubble,
                -halfContainer + interfaceInset - 0.001
            )
            XCTAssertLessThanOrEqual(
                placement.bubbleCenterOffset + halfBubble,
                halfContainer - interfaceInset + 0.001
            )
            XCTAssertLessThanOrEqual(
                abs(placement.pointerOffset),
                maximumPointerOffset + 0.001
            )
        }

        for anchorOffset in [-215.0, 0, 215.0] {
            let placement = PopupHorizontalPlacement.resolve(
                anchorOffset: anchorOffset,
                containerWidth: containerWidth,
                bubbleWidth: bubbleWidth,
                horizontalInset: interfaceInset,
                pointerEdgeInset: pointerEdgeInset
            )
            XCTAssertEqual(
                placement.bubbleCenterOffset + placement.pointerOffset,
                anchorOffset,
                accuracy: 0.001
            )
        }
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
    func testInterruptedPillMotionRetargetsWithoutAPlateau() {
        let source = StatusItemArtwork.centerX(for: 0)
        let target = StatusItemArtwork.centerX(for: 1)

        for style in IndicatorAnimationStyle.allCases {
            let forward = StatusPillMotion(
                fromX: source,
                toX: target,
                startTime: 10,
                style: style
            )
            let interruptionTime = 10 + forward.duration * 0.42
            let interruptedFrame = forward.frame(at: interruptionTime)
            let reverse = StatusPillMotion(
                fromX: interruptedFrame.x,
                toX: source,
                initialWidth: interruptedFrame.width,
                initialHeight: interruptedFrame.height,
                initialWaist: interruptedFrame.waist,
                initialAppearanceProgress:
                    1 - interruptedFrame.progress,
                startTime: interruptionTime,
                style: style,
                isRetargeting: true
            )
            let firstFrame = reverse.frame(at: interruptionTime)

            XCTAssertEqual(
                firstFrame.x,
                interruptedFrame.x,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                firstFrame.width,
                interruptedFrame.width,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                firstFrame.height,
                interruptedFrame.height,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                firstFrame.waist,
                interruptedFrame.waist,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                firstFrame.progress,
                1 - interruptedFrame.progress,
                accuracy: 0.0001
            )

            for refreshRate in [60.0, 120.0] {
                let nextFrame = reverse.frame(
                    at: interruptionTime + 1 / refreshRate
                )
                XCTAssertLessThan(
                    nextFrame.x + nextFrame.width / 2,
                    firstFrame.x + firstFrame.width / 2,
                    "Retargeting \(style) paused at \(refreshRate) Hz"
                )
            }

            XCTAssertEqual(
                reverse.frame(at: interruptionTime + reverse.duration),
                .resting(at: source)
            )
            XCTAssertLessThanOrEqual(reverse.duration, 0.30)
        }
    }

    @MainActor
    func testStatusBarContinuationUsesThePresentedFrameWithoutPausing() {
        let source = StatusItemArtwork.centerX(for: 0)
        let target = StatusItemArtwork.centerX(for: 1)
        let presentedFrame = StatusPillFrame(
            x: target - 4,
            width: 18,
            height: 6,
            waist: 0.65,
            progress: 0.48,
            isComplete: false
        )
        let startTime: TimeInterval = 30
        let continuation = StatusPillMotion.statusBarContinuation(
            from: presentedFrame,
            toX: source,
            startTime: startTime,
            sizeScale: 1,
            itemWidth: StatusItemArtwork.itemWidth,
            shapeStyle: .standard
        )

        XCTAssertTrue(continuation.isRetargeting)
        let first = continuation.frame(at: startTime)
        XCTAssertEqual(first.x, presentedFrame.x, accuracy: 0.0001)
        XCTAssertEqual(first.width, presentedFrame.width, accuracy: 0.0001)
        XCTAssertEqual(first.height, presentedFrame.height, accuracy: 0.0001)
        XCTAssertEqual(first.waist, presentedFrame.waist, accuracy: 0.0001)

        for refreshRate in [60.0, 120.0] {
            let next = continuation.frame(
                at: startTime + 1 / refreshRate
            )
            XCTAssertLessThan(
                next.x,
                first.x,
                "Status-bar continuation paused at \(refreshRate) Hz"
            )
            XCTAssertLessThan(
                next.waist,
                first.waist,
                "The interrupted bridge must settle continuously"
            )
        }

        XCTAssertEqual(
            continuation.frame(at: startTime + continuation.duration),
            .resting(at: source)
        )
    }

    @MainActor
    func testStatusBarContinuationScalesDurationForShortReversal() {
        let target = StatusItemArtwork.centerX(for: 0)
        let presentedFrame = StatusPillFrame(
            x: target + 1.5,
            width: 13,
            height: 7,
            waist: 0.12,
            progress: 0.16,
            isComplete: false
        )
        let startTime: TimeInterval = 40
        let continuation = StatusPillMotion.statusBarContinuation(
            from: presentedFrame,
            toX: target,
            startTime: startTime,
            sizeScale: 1,
            itemWidth: StatusItemArtwork.itemWidth,
            shapeStyle: .standard
        )

        XCTAssertLessThan(
            continuation.duration,
            OrbitMotion.classicDuration,
            "A near-endpoint reversal must not replay a full transition"
        )

        for refreshRate in [60.0, 120.0] {
            let next = continuation.frame(
                at: startTime + 1 / refreshRate
            )
            XCTAssertLessThan(
                abs(next.x - target),
                abs(presentedFrame.x - target),
                "A short reversal must advance on its first visible frame"
            )
            XCTAssertLessThan(
                next.width,
                presentedFrame.width,
                "The interrupted shape must settle instead of stretching again"
            )
        }
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
    func testHoverMotionUsesSingleStepProfile() {
        let resting = CGSize(width: 1, height: 1)
        let entry = StatusHoverMotion(
            index: 1,
            fromScale: resting,
            isHovered: true,
            isActive: false,
            startTime: 10
        )
        XCTAssertEqual(entry.duration, 0.30, accuracy: 0.001)
        XCTAssertEqual(entry.targetScale.width, 11.75 / 4.5, accuracy: 0.001)
        XCTAssertEqual(entry.targetScale.height, 7.75 / 4.5, accuracy: 0.001)

        let midpoint = entry.frame(at: 10 + entry.duration * 0.5)
        XCTAssertGreaterThan(midpoint.scale.width, resting.width)
        XCTAssertLessThanOrEqual(midpoint.scale.width, entry.targetScale.width)
        XCTAssertLessThanOrEqual(midpoint.scale.height, entry.targetScale.height)
        let finished = entry.frame(at: 10 + entry.duration)
        XCTAssertEqual(finished.scale.width, entry.targetScale.width, accuracy: 0.001)
        XCTAssertEqual(finished.scale.height, entry.targetScale.height, accuracy: 0.001)

        let exit = StatusHoverMotion(
            index: 1,
            fromScale: entry.targetScale,
            isHovered: false,
            isActive: false,
            startTime: 20
        )
        XCTAssertEqual(exit.duration, 0.30, accuracy: 0.001)
        let exitFinished = exit.frame(at: 20 + exit.duration)
        XCTAssertTrue(exitFinished.isComplete)
        XCTAssertEqual(exitFinished.scale, resting)

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
    func testApplicationPreviewUsesClassicStretchAndSmoothExit() {
        let entry = StatusApplicationPreviewMotion(
            isPresenting: true,
            fromFrame: .hidden,
            startTime: 10
        )
        let stretched = entry.frame(
            at: 10 + entry.duration * 0.62
        )
        let settled = entry.frame(
            at: 10 + entry.duration * 0.82
        )
        let firstSixtyHertzFrame = entry.frame(at: 10 + 1.0 / 60.0)
        XCTAssertGreaterThan(stretched.expansion, 0.1)
        XCTAssertGreaterThan(settled.expansion, stretched.expansion)
        XCTAssertGreaterThan(
            firstSixtyHertzFrame.expansion,
            0.005,
            "The preview should not appear stationary in its first visible frame"
        )
        XCTAssertEqual(
            entry.frame(at: 10 + entry.duration),
            .visible
        )

        let exit = StatusApplicationPreviewMotion(
            isPresenting: false,
            fromFrame: .visible,
            startTime: 20
        )
        let middle = exit.frame(at: 20 + exit.duration / 2)
        XCTAssertGreaterThan(middle.expansion, 0)
        XCTAssertLessThan(middle.expansion, 1)
        XCTAssertEqual(exit.frame(at: 20 + exit.duration), .hidden)
    }

    @MainActor
    func testApplicationPreviewRapidReversalsStartFromThePresentedFrame() {
        for refreshRate in [60.0, 120.0] {
            let enter = StatusApplicationPreviewMotion(
                isPresenting: true,
                fromFrame: .hidden,
                startTime: 10
            )
            let interruptionTime = 10 + enter.duration * 0.43
            let presented = enter.frame(at: interruptionTime)
            let exit = StatusApplicationPreviewMotion(
                isPresenting: false,
                fromFrame: presented,
                startTime: interruptionTime
            )

            XCTAssertEqual(
                exit.frame(at: interruptionTime),
                presented,
                "Exit must reuse the exact visible frame at \(refreshRate) Hz"
            )
            let firstExitFrame = exit.frame(
                at: interruptionTime + 1 / refreshRate
            )
            XCTAssertLessThan(firstExitFrame.expansion, presented.expansion)
            XCTAssertLessThan(firstExitFrame.iconOpacity, presented.iconOpacity)

            let reverseTime = interruptionTime + 1 / refreshRate
            let reenter = StatusApplicationPreviewMotion(
                isPresenting: true,
                fromFrame: firstExitFrame,
                startTime: reverseTime
            )
            XCTAssertEqual(
                reenter.frame(at: reverseTime),
                firstExitFrame,
                "A second reversal must not insert a ghost frame"
            )
            let firstReentryFrame = reenter.frame(
                at: reverseTime + 1 / refreshRate
            )
            XCTAssertGreaterThan(
                firstReentryFrame.expansion,
                firstExitFrame.expansion
            )
            XCTAssertGreaterThan(
                firstReentryFrame.iconOpacity,
                firstExitFrame.iconOpacity
            )
        }
    }

    @MainActor
    func testApplicationPreviewExpansionPreservesNeighborSpacing() throws {
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let renderer = StatusIndicatorImageRenderer(
            count: 3,
            applicationPreviewIndex: 1,
            applicationIcons: [icon, icon]
        )
        let hover = StatusHoverMotion(
            index: 1,
            fromScale: CGSize(width: 1, height: 1),
            isHovered: true,
            isActive: false,
            startTime: 0
        )
        renderer.update(
            pill: .resting(at: StatusItemArtwork.centerX(for: 0)),
            activeIndex: 0,
            hoverScales: [1: hover.targetScale],
            applicationPreviewFrame: .visible
        )

        let left = try XCTUnwrap(renderer.indicatorCenterX(at: 0))
        let preview = try XCTUnwrap(renderer.indicatorCenterX(at: 1))
        let right = try XCTUnwrap(renderer.indicatorCenterX(at: 2))
        let expectedDistance = StatusItemArtwork.itemWidth
            + renderer.currentApplicationPreviewExtraWidth / 2

        XCTAssertGreaterThan(renderer.currentApplicationPreviewExtraWidth, 0)
        XCTAssertEqual(preview - left, expectedDistance, accuracy: 0.001)
        XCTAssertEqual(right - preview, expectedDistance, accuracy: 0.001)
        XCTAssertEqual(renderer.indicatorIndex(atImageX: preview), 1)
    }

    @MainActor
    func testExpandedPreviewMapsMovingPillContinuouslyAcrossItsCell() {
        let previewX: CGFloat = 100
        let itemWidth: CGFloat = 20
        let extraWidth: CGFloat = 40

        XCTAssertEqual(
            StatusIndicatorImageRenderer.applicationPreviewLayoutShift(
                baseX: previewX - itemWidth,
                previewBaseX: previewX,
                itemWidth: itemWidth,
                extraWidth: extraWidth
            ),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StatusIndicatorImageRenderer.applicationPreviewLayoutShift(
                baseX: previewX,
                previewBaseX: previewX,
                itemWidth: itemWidth,
                extraWidth: extraWidth
            ),
            extraWidth / 2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StatusIndicatorImageRenderer.applicationPreviewLayoutShift(
                baseX: previewX + itemWidth,
                previewBaseX: previewX,
                itemWidth: itemWidth,
                extraWidth: extraWidth
            ),
            extraWidth,
            accuracy: 0.0001
        )

        let immediatelyBefore =
            StatusIndicatorImageRenderer.applicationPreviewLayoutShift(
                baseX: previewX - 0.001,
                previewBaseX: previewX,
                itemWidth: itemWidth,
                extraWidth: extraWidth
            )
        let immediatelyAfter =
            StatusIndicatorImageRenderer.applicationPreviewLayoutShift(
                baseX: previewX + 0.001,
                previewBaseX: previewX,
                itemWidth: itemWidth,
                extraWidth: extraWidth
            )
        XCTAssertLessThan(
            immediatelyAfter - immediatelyBefore,
            0.01,
            "Crossing an expanded preview must not jump by half its width"
        )
    }

    @MainActor
    func testReverseTransitionPreservesRenderedAppearanceAtInterruption() throws {
        let renderer = StatusIndicatorImageRenderer(
            count: 2,
            indicatorKinds: [
                .desktop(colorIndex: 0),
                .fullscreen(colorIndex: 1)
            ],
            indicatorColors: [.systemRed, .systemBlue]
        )
        let source = StatusItemArtwork.centerX(for: 0)
        let target = StatusItemArtwork.centerX(for: 1)
        let forward = StatusPillMotion(
            fromX: source,
            toX: target,
            startTime: 20,
            style: .continuous
        )
        let interruptionTime = 20 + forward.duration * 0.42
        let interruptedFrame = forward.frame(at: interruptionTime)
        renderer.update(
            pill: interruptedFrame,
            activeIndex: 1,
            transitionSourceIndex: 0
        )
        let forwardPixels = try XCTUnwrap(
            renderer.image.representations.first as? NSBitmapImageRep
        )
        let byteCount =
            forwardPixels.bytesPerRow * forwardPixels.pixelsHigh
        let forwardBytes = Array(
            UnsafeBufferPointer(
                start: try XCTUnwrap(forwardPixels.bitmapData),
                count: byteCount
            )
        )

        let reverse = StatusPillMotion(
            fromX: interruptedFrame.x,
            toX: source,
            initialWidth: interruptedFrame.width,
            initialHeight: interruptedFrame.height,
            initialWaist: interruptedFrame.waist,
            initialAppearanceProgress: 1 - interruptedFrame.progress,
            startTime: interruptionTime,
            style: .continuous,
            isRetargeting: true
        )
        renderer.update(
            pill: reverse.frame(at: interruptionTime),
            activeIndex: 0,
            transitionSourceIndex: 1
        )
        let reversePixels = try XCTUnwrap(
            renderer.image.representations.first as? NSBitmapImageRep
        )
        let reverseBytes = Array(
            UnsafeBufferPointer(
                start: try XCTUnwrap(reversePixels.bitmapData),
                count: byteCount
            )
        )

        XCTAssertEqual(
            reverseBytes,
            forwardBytes,
            "A reverse gesture must begin from the exact rendered frame"
        )
    }

    @MainActor
    func testForwardRetargetPreservesRenderedAppearanceAtInterruption() throws {
        let renderer = StatusIndicatorImageRenderer(
            count: 3,
            indicatorKinds: [
                .desktop(colorIndex: 0),
                .fullscreen(colorIndex: 1),
                .desktop(colorIndex: 2)
            ],
            indicatorColors: [
                .systemRed,
                .systemBlue,
                .systemGreen
            ]
        )
        let source = StatusItemArtwork.centerX(for: 0)
        let middle = StatusItemArtwork.centerX(for: 1)
        let target = StatusItemArtwork.centerX(for: 2)
        let forward = StatusPillMotion(
            fromX: source,
            toX: middle,
            startTime: 30,
            style: .continuous
        )
        let interruptionTime = 30 + forward.duration * 0.42
        let interruptedFrame = forward.frame(at: interruptionTime)
        renderer.update(
            pill: interruptedFrame,
            activeIndex: 1,
            transitionSourceIndex: 0
        )
        let initialPixels = try XCTUnwrap(
            renderer.image.representations.first as? NSBitmapImageRep
        )
        let byteCount =
            initialPixels.bytesPerRow * initialPixels.pixelsHigh
        let initialBytes = Array(
            UnsafeBufferPointer(
                start: try XCTUnwrap(initialPixels.bitmapData),
                count: byteCount
            )
        )
        let interruptedPresentation = try XCTUnwrap(
            renderer.transitionPresentationSnapshot(
                for: interruptedFrame
            )
        )

        let retarget = StatusPillMotion(
            fromX: interruptedFrame.x,
            toX: target,
            initialWidth: interruptedFrame.width,
            initialHeight: interruptedFrame.height,
            initialWaist: interruptedFrame.waist,
            startTime: interruptionTime,
            style: .continuous,
            isRetargeting: true
        )
        renderer.update(
            pill: retarget.frame(at: interruptionTime),
            activeIndex: 2,
            transitionSourceIndex: 1,
            interruptedTransitionPresentation:
                interruptedPresentation
        )
        let retargetedPixels = try XCTUnwrap(
            renderer.image.representations.first as? NSBitmapImageRep
        )
        let retargetedBytes = Array(
            UnsafeBufferPointer(
                start: try XCTUnwrap(retargetedPixels.bitmapData),
                count: byteCount
            )
        )

        XCTAssertEqual(
            retargetedBytes,
            initialBytes,
            "A rapid A → B → C gesture must not flash at retarget"
        )

        let secondInterruptionTime =
            interruptionTime + retarget.duration * 0.37
        let secondInterruptedFrame = retarget.frame(
            at: secondInterruptionTime
        )
        renderer.update(
            pill: secondInterruptedFrame,
            activeIndex: 2,
            transitionSourceIndex: 1,
            interruptedTransitionPresentation:
                interruptedPresentation
        )
        let secondInitialPixels = try XCTUnwrap(
            renderer.image.representations.first as? NSBitmapImageRep
        )
        let secondInitialBytes = Array(
            UnsafeBufferPointer(
                start: try XCTUnwrap(secondInitialPixels.bitmapData),
                count: byteCount
            )
        )
        let secondInterruptedPresentation = try XCTUnwrap(
            renderer.transitionPresentationSnapshot(
                for: secondInterruptedFrame
            )
        )
        let secondRetarget = StatusPillMotion(
            fromX: secondInterruptedFrame.x,
            toX: middle,
            initialWidth: secondInterruptedFrame.width,
            initialHeight: secondInterruptedFrame.height,
            initialWaist: secondInterruptedFrame.waist,
            startTime: secondInterruptionTime,
            style: .continuous,
            isRetargeting: true
        )
        renderer.update(
            pill: secondRetarget.frame(at: secondInterruptionTime),
            activeIndex: 1,
            transitionSourceIndex: 2,
            interruptedTransitionPresentation:
                secondInterruptedPresentation
        )
        let secondRetargetPixels = try XCTUnwrap(
            renderer.image.representations.first as? NSBitmapImageRep
        )
        let secondRetargetBytes = Array(
            UnsafeBufferPointer(
                start: try XCTUnwrap(secondRetargetPixels.bitmapData),
                count: byteCount
            )
        )

        XCTAssertEqual(
            secondRetargetBytes,
            secondInitialBytes,
            "Repeated retargets must preserve the exact rendered frame"
        )
    }

    @MainActor
    func testApplicationPreviewCollapsesContinuouslyDuringSpaceTransition() {
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let renderer = StatusIndicatorImageRenderer(
            count: 3,
            applicationPreviewIndex: 0,
            applicationIcons: [icon, icon],
            maximumApplicationPreviewIconCount: 2
        )
        let source = StatusItemArtwork.centerX(for: 0)
        let target = StatusItemArtwork.centerX(for: 1)
        renderer.update(
            pill: .resting(at: source),
            activeIndex: 0,
            applicationPreviewFrame: .visible
        )
        let expandedWidth = renderer.currentApplicationPreviewExtraWidth

        let transition = StatusPillMotion(
            fromX: source,
            toX: target,
            startTime: 0,
            style: .continuous
        )
        let transitionFrame = transition.frame(
            at: transition.duration * 0.20
        )
        let exit = StatusApplicationPreviewMotion(
            isPresenting: false,
            fromFrame: .visible,
            startTime: 0
        )
        let firstExitFrame = exit.frame(at: 1.0 / 120.0)
        renderer.update(
            pill: transitionFrame,
            activeIndex: 1,
            transitionSourceIndex: 0,
            applicationPreviewFrame: firstExitFrame
        )

        XCTAssertGreaterThan(
            renderer.currentApplicationPreviewExtraWidth,
            0
        )
        XCTAssertLessThan(
            renderer.currentApplicationPreviewExtraWidth,
            expandedWidth
        )

        renderer.update(
            pill: transitionFrame,
            activeIndex: 1,
            transitionSourceIndex: 0,
            applicationPreviewFrame: .hidden
        )
        XCTAssertEqual(
            renderer.currentApplicationPreviewExtraWidth,
            0,
            accuracy: 0.0001
        )
    }

    @MainActor
    func testExpandedActivePreviewHandsOffToSpaceTransitionWithoutFlash()
        throws
    {
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let renderer = StatusIndicatorImageRenderer(
            count: 3,
            applicationPreviewIndex: 0,
            applicationIcons: [icon, icon],
            maximumApplicationPreviewIconCount: 2
        )
        let source = StatusItemArtwork.centerX(for: 0)
        let target = StatusItemArtwork.centerX(for: 1)
        renderer.update(
            pill: .resting(at: source),
            activeIndex: 0,
            applicationPreviewFrame: .visible
        )
        let expandedPixels = try pixelBytes(of: renderer.image)

        let transition = StatusPillMotion(
            fromX: source,
            toX: target,
            startTime: 0,
            style: .continuous
        )
        renderer.update(
            pill: transition.frame(at: 0),
            activeIndex: 1,
            transitionSourceIndex: 0,
            applicationPreviewFrame: .visible,
            applicationPreviewTracksPill: true
        )

        XCTAssertEqual(
            try pixelBytes(of: renderer.image),
            expandedPixels,
            "Starting a swipe must reuse the expanded pill's exact pixels"
        )

        let restingTarget = StatusPillFrame.resting(at: target)
        renderer.update(
            pill: restingTarget,
            activeIndex: 1,
            applicationPreviewFrame: .hidden,
            applicationPreviewTracksPill: true
        )
        let trackedRestingPixels = try pixelBytes(of: renderer.image)
        renderer.setApplicationPreview(index: nil, icons: [])
        renderer.update(
            pill: restingTarget,
            activeIndex: 1
        )

        XCTAssertEqual(
            trackedRestingPixels,
            try pixelBytes(of: renderer.image),
            "Finishing the collapse must hand off to the normal pill exactly"
        )
    }

    @MainActor
    func testColorUpdateRedrawsPersistentArtworkInPlace() throws {
        let renderer = StatusIndicatorImageRenderer(
            count: 1,
            indicatorColors: [.systemRed]
        )
        let image = renderer.image
        renderer.update(
            pill: .resting(at: StatusItemArtwork.centerX(for: 0)),
            activeIndex: 0
        )

        renderer.setIndicatorColors([.systemBlue])
        renderer.update(
            pill: .resting(at: StatusItemArtwork.centerX(for: 0)),
            activeIndex: 0
        )

        XCTAssertTrue(renderer.image === image)
        let data = try XCTUnwrap(renderer.image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let center = try XCTUnwrap(
            bitmap.colorAt(
                x: bitmap.pixelsWide / 2,
                y: bitmap.pixelsHigh / 2
            )
        )
        XCTAssertGreaterThan(center.blueComponent, center.redComponent)
    }

    @MainActor
    func testDarkEdgeUpdateRedrawsPersistentArtworkInPlace() throws {
        let renderer = StatusIndicatorImageRenderer(
            count: 1,
            indicatorColors: [.systemBlue]
        )
        let image = renderer.image
        let pill = StatusPillFrame.resting(
            at: StatusItemArtwork.centerX(for: 0)
        )
        renderer.update(pill: pill, activeIndex: 0)
        let plainPixels = try pixelBytes(of: image)

        renderer.setShowsDarkEdge(true)
        renderer.update(pill: pill, activeIndex: 0)
        let edgedPixels = try pixelBytes(of: image)

        XCTAssertTrue(renderer.image === image)
        XCTAssertNotEqual(edgedPixels, plainPixels)

        renderer.setShowsDarkEdge(false)
        renderer.update(pill: pill, activeIndex: 0)
        XCTAssertEqual(try pixelBytes(of: image), plainPixels)
    }

    @MainActor
    func testPreparedApplicationIconsTrackVisualAppearanceEfficiently()
        throws
    {
        func solidIcon(_ color: NSColor) -> NSImage {
            NSImage(
                size: NSSize(width: 32, height: 32),
                flipped: false
            ) { rect in
                color.setFill()
                NSBezierPath(rect: rect).fill()
                return true
            }
        }

        let appearance = try XCTUnwrap(
            NSAppearance(named: .aqua)
        )
        let first = try XCTUnwrap(
            SpaceApplicationPresentationFactory.prepareIcon(
                solidIcon(.systemRed),
                appearance: appearance
            )
        )
        let repeated = try XCTUnwrap(
            SpaceApplicationPresentationFactory.prepareIcon(
                solidIcon(.systemRed),
                appearance: appearance
            )
        )
        let changed = try XCTUnwrap(
            SpaceApplicationPresentationFactory.prepareIcon(
                solidIcon(.systemBlue),
                appearance: appearance
            )
        )

        XCTAssertEqual(first.image.size, NSSize(width: 32, height: 32))
        let bitmap = try XCTUnwrap(
            first.image.representations.first as? NSBitmapImageRep
        )
        XCTAssertEqual(bitmap.pixelsWide, 64)
        XCTAssertEqual(bitmap.pixelsHigh, 64)
        XCTAssertEqual(first.revision, repeated.revision)
        XCTAssertNotEqual(first.revision, changed.revision)
    }

    @MainActor
    func testApplicationPreviewScalesProportionallyInSettingsDemo() {
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let menuRenderer = StatusIndicatorImageRenderer(
            count: 3,
            sizeScale: 1,
            imageHeight: StatusItemArtwork.imageHeight,
            applicationPreviewIndex: 1,
            applicationIcons: [icon, icon]
        )
        menuRenderer.update(
            pill: .resting(at: StatusItemArtwork.centerX(for: 0)),
            activeIndex: 0,
            applicationPreviewFrame: .visible
        )

        let demoScale: CGFloat = 2.15
        let demoRenderer = StatusIndicatorImageRenderer(
            count: 3,
            sizeScale: demoScale,
            imageHeight: SyncedIndicatorArtworkView.previewHeight(
                for: demoScale
            ),
            applicationPreviewIndex: 1,
            applicationIcons: [icon, icon]
        )
        demoRenderer.update(
            pill: .resting(
                at: StatusItemArtwork.centerX(
                    for: 0,
                    sizeScale: demoScale
                )
            ),
            activeIndex: 0,
            applicationPreviewFrame: .visible
        )

        XCTAssertEqual(
            demoRenderer.currentApplicationPreviewExtraWidth,
            menuRenderer.currentApplicationPreviewExtraWidth * demoScale,
            accuracy: 0.001
        )
    }

    @MainActor
    func testApplicationPreviewFitsCrowdedMenuBarProportionally() {
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let renderer = StatusIndicatorImageRenderer(
            count: 8,
            applicationPreviewIndex: 3,
            applicationIcons: Array(repeating: icon, count: 12),
            maximumApplicationPreviewIconCount: 12,
            maximumVisibleContentWidth:
                StatusItemArtwork.maximumStatusItemWidth
        )
        renderer.update(
            pill: .resting(at: StatusItemArtwork.centerX(for: 0)),
            activeIndex: 0,
            applicationPreviewFrame: .visible
        )

        XCTAssertLessThan(renderer.currentContentScale, 1)
        XCTAssertLessThanOrEqual(
            renderer.currentStatusItemWidth,
            StatusItemArtwork.maximumStatusItemWidth + 0.001
        )
    }

    @MainActor
    func testApplicationPreviewKeepsStationaryPointerOnHoveredIndicator() throws {
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let renderer = StatusIndicatorImageRenderer(
            count: 3,
            applicationPreviewIndex: 1,
            applicationIcons: [icon, icon]
        )
        let initialCenter = try XCTUnwrap(renderer.indicatorCenterX(at: 1))

        for expansion in stride(from: CGFloat(0), through: 1.035, by: 0.05) {
            renderer.update(
                pill: .resting(at: StatusItemArtwork.centerX(for: 0)),
                activeIndex: 0,
                applicationPreviewFrame: StatusApplicationPreviewFrame(
                    expansion: expansion,
                    iconOpacity: min(expansion, 1),
                    isComplete: false
                )
            )

            // The button expands towards its leading edge, so a stationary
            // screen-space pointer moves right by half the added width in the
            // renderer's fixed image coordinate system.
            let stationaryPointerX = initialCenter
                + renderer.currentApplicationPreviewExtraWidth / 2
            XCTAssertEqual(
                renderer.indicatorIndex(atImageX: stationaryPointerX),
                1,
                "Lost hover identity at expansion \(expansion)"
            )
        }
    }

    @MainActor
    func testApplicationPreviewTimingSettlesAtSixtyAndOneTwentyHertz() {
        for refreshRate in [60.0, 120.0] {
            let motion = StatusApplicationPreviewMotion(
                isPresenting: true,
                fromFrame: .hidden,
                startTime: 0
            )
            let frameCount = Int(ceil(motion.duration * refreshRate))
            var frame = StatusApplicationPreviewFrame.hidden
            for index in 0...frameCount {
                frame = motion.frame(
                    at: min(Double(index) / refreshRate, motion.duration)
                )
            }
            frame = motion.frame(at: motion.duration)
            XCTAssertEqual(frame, .visible)
        }
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

        for style in IndicatorAnimationStyle.allCases {
            for (sourceIndex, targetIndex) in [
                (0, count - 1),
                (count - 1, 0)
            ] {
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
                    style: style
                )

                for step in 0...120 {
                    let timestamp = motion.duration * Double(step) / 120
                    renderer.update(
                        pill: motion.frame(at: timestamp),
                        activeIndex: targetIndex,
                        transitionSourceIndex:
                            style.blendsIndicatorAppearanceDuringTransition
                                ? sourceIndex
                                : nil,
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
                        return XCTFail(
                            "Could not inspect \(style) transition frame"
                        )
                    }
                    XCTAssertGreaterThan(
                        bounds.minX,
                        0,
                        "\(style) clipped at step \(step)"
                    )
                    XCTAssertLessThan(
                        bounds.maxX,
                        CGFloat(bitmap.pixelsWide),
                        "\(style) clipped at step \(step)"
                    )
                }
            }
        }
    }

    @MainActor
    func testDarkEdgeChangesDesktopAndFullscreenIndicators() throws {
        let plainDesktop = StatusIndicatorImageRenderer(
            count: 1,
            indicatorColors: [.systemBlue]
        )
        let outlinedDesktop = StatusIndicatorImageRenderer(
            count: 1,
            indicatorColors: [.systemBlue],
            showsDarkEdge: true
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
            showsDarkEdge: true
        )

        XCTAssertNotEqual(
            plainFullscreen.image.tiffRepresentation,
            outlinedFullscreen.image.tiffRepresentation
        )
    }

    @MainActor
    func testOptionalOutlineIsConsistentlyDarkForDarkIndicatorColors()
        throws
    {
        let plain = StatusIndicatorImageRenderer(
            count: 1,
            indicatorColors: [.systemBlue]
        )
        let outlined = StatusIndicatorImageRenderer(
            count: 1,
            indicatorColors: [.systemBlue],
            showsDarkEdge: true
        )
        let center = StatusItemArtwork.centerX(for: 0)
        plain.update(
            pill: .resting(at: center),
            activeIndex: 0
        )
        outlined.update(
            pill: .resting(at: center),
            activeIndex: 0
        )

        let plainBitmap = try XCTUnwrap(
            plain.image.representations.first as? NSBitmapImageRep
        )
        let outlinedBitmap = try XCTUnwrap(
            outlined.image.representations.first as? NSBitmapImageRep
        )
        func alphaWeightedLuminance(
            in bitmap: NSBitmapImageRep
        ) -> CGFloat {
            var weightedLuminance: CGFloat = 0
            var accumulatedAlpha: CGFloat = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y) else {
                        continue
                    }
                    let alpha = color.alphaComponent
                    accumulatedAlpha += alpha
                    weightedLuminance += alpha * (
                        0.2126 * color.redComponent
                            + 0.7152 * color.greenComponent
                            + 0.0722 * color.blueComponent
                    )
                }
            }
            return weightedLuminance / max(accumulatedAlpha, 0.001)
        }

        XCTAssertLessThan(
            alphaWeightedLuminance(in: outlinedBitmap),
            alphaWeightedLuminance(in: plainBitmap),
            "The optional edge must stay dark instead of turning white"
        )
    }

    @MainActor
    func testIncreasedContrastStrengthensIndicatorsWithoutChangingGeometry() throws {
        let kinds: [SpaceIndicatorKind] = [
            .desktop(colorIndex: 0),
            .fullscreen(colorIndex: 0)
        ]
        let normal = StatusIndicatorImageRenderer(
            count: kinds.count,
            indicatorKinds: kinds,
            indicatorColors: [.systemBlue],
            showsDarkEdge: true
        )
        let increased = StatusIndicatorImageRenderer(
            count: kinds.count,
            indicatorKinds: kinds,
            indicatorColors: [.systemBlue],
            showsDarkEdge: true,
            increasedContrast: true
        )

        let normalBitmap = try XCTUnwrap(
            NSBitmapImageRep(
                data: try XCTUnwrap(normal.image.tiffRepresentation)
            )
        )
        let increasedBitmap = try XCTUnwrap(
            NSBitmapImageRep(
                data: try XCTUnwrap(increased.image.tiffRepresentation)
            )
        )
        XCTAssertEqual(normal.imageSize, increased.imageSize)
        XCTAssertEqual(
            opaquePixelBounds(in: normalBitmap, minimumAlpha: 0.01),
            opaquePixelBounds(in: increasedBitmap, minimumAlpha: 0.01)
        )
        XCTAssertGreaterThan(
            accumulatedAlpha(in: increasedBitmap),
            accumulatedAlpha(in: normalBitmap)
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
    func testFullscreenDarkEdgeSurroundsColoredStroke() throws {
        let sizeScale: CGFloat = 1.7
        let plainRenderer = StatusIndicatorImageRenderer(
            count: 1,
            indicatorKinds: [.fullscreen(colorIndex: 0)],
            indicatorColors: [.systemYellow],
            sizeScale: sizeScale
        )
        let renderer = StatusIndicatorImageRenderer(
            count: 1,
            indicatorKinds: [.fullscreen(colorIndex: 0)],
            indicatorColors: [.systemYellow],
            showsDarkEdge: true,
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
        plainRenderer.update(
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
        let plainData = try XCTUnwrap(
            plainRenderer.image.tiffRepresentation
        )
        let plainBitmap = try XCTUnwrap(
            NSBitmapImageRep(data: plainData)
        )
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

        func solidColoredPixels(in bitmap: NSBitmapImageRep) -> [Int] {
            (0..<centerX).filter { x in
                guard let color = bitmap.colorAt(x: x, y: centerY) else {
                    return false
                }
                return color.alphaComponent > 0.8
                    && color.redComponent > 0.8
                    && color.greenComponent > 0.6
                    && color.blueComponent < 0.4
            }
        }
        let edgedSolidPixels = solidColoredPixels(in: bitmap)
        let plainSolidPixels = solidColoredPixels(in: plainBitmap)
        XCTAssertEqual(
            edgedSolidPixels,
            plainSolidPixels,
            "Enabling the edge must not move the full-screen color stroke"
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

    private func accumulatedAlpha(in bitmap: NSBitmapImageRep) -> CGFloat {
        var result: CGFloat = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                result += bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
            }
        }
        return result
    }

    private func pixelBytes(of image: NSImage) throws -> [UInt8] {
        let bitmap = try XCTUnwrap(
            image.representations.first as? NSBitmapImageRep
        )
        let data = try XCTUnwrap(bitmap.bitmapData)
        return Array(
            UnsafeBufferPointer(
                start: data,
                count: bitmap.bytesPerRow * bitmap.pixelsHigh
            )
        )
    }

    @MainActor
    private func waitForPendingReads(
        _ count: Int,
        in reader: ControlledSpacesReader
    ) async {
        for _ in 0..<100 where reader.pendingReadIdentifiers.count < count {
            await Task.yield()
        }
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
private final class ControlledSpacesReader: SpacesReading {
    private var nextIdentifier = 0
    private var continuations: [
        Int: CheckedContinuation<SpaceSnapshot?, Never>
    ] = [:]

    var pendingReadIdentifiers: [Int] {
        continuations.keys.sorted()
    }

    func start(onChange: @escaping () -> Void) {}
    func stop() {}

    func read() async -> SpaceSnapshot? {
        let identifier = nextIdentifier
        nextIdentifier += 1
        return await withCheckedContinuation { continuation in
            continuations[identifier] = continuation
        }
    }

    func resume(read identifier: Int, with snapshot: SpaceSnapshot?) {
        continuations.removeValue(forKey: identifier)?.resume(
            returning: snapshot
        )
    }
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
