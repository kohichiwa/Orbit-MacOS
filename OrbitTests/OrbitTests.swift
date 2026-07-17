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

    func testKeepsFullscreenSpacesForNavigationButNotForDots() {
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
        XCTAssertEqual(snapshot?.activeIndex, 1)
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

        await viewModel.select(1)

        XCTAssertEqual(viewModel.spaceCount, 2)
        XCTAssertEqual(viewModel.activeIndex, 1)
        XCTAssertEqual(controller.moves, [.next, .next])
        XCTAssertNil(viewModel.message)
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

    private func opaquePixelBounds(in bitmap: NSBitmapImageRep) -> NSRect? {
        var minimumX = bitmap.pixelsWide
        var minimumY = bitmap.pixelsHigh
        var maximumX = -1
        var maximumY = -1

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.8 else {
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
