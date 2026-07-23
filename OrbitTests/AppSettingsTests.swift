import AppKit
import Combine
import XCTest

@testable import Orbit

@MainActor
final class AppSettingsTests: XCTestCase {
    func testSettingsWindowIsFixedAndTransparent() {
        let suiteName = "OrbitTests.settings.window.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let viewModel = SpaceViewModel(
            colorAssignments: settings,
            previewSnapshot: SpaceSnapshot(
                identifiers: [11, 12, 13],
                activeIndex: 1
            )
        )
        let controller = SettingsWindowController(
            settings: settings,
            viewModel: viewModel
        )
        guard let window = controller.window else {
            return XCTFail("Could not create settings window")
        }
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor.alphaComponent, 0, accuracy: 0.001)
        XCTAssertEqual(window.minSize, window.maxSize)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertFalse(window.hidesOnDeactivate)
        XCTAssertEqual(window.level, .floating)
        XCTAssertGreaterThan(window.contentMaxSize.height, window.contentMaxSize.width)
        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))

        guard
            let contentView = window.contentView,
            let visualEffect = visualEffectView(in: contentView)
        else {
            return XCTFail("Settings window must contain a visual effect view")
        }
        XCTAssertEqual(visualEffect.blendingMode, .behindWindow)
        XCTAssertEqual(visualEffect.material, .underWindowBackground)
        XCTAssertEqual(visualEffect.state, .followsWindowActiveState)
        XCTAssertEqual(visualEffect.alphaValue, 1)
        XCTAssertEqual(window.frameAutosaveName, "OrbitSettingsWindow")
        XCTAssertTrue(
            window.standardWindowButton(.miniaturizeButton)?.isHidden == true
        )
        XCTAssertTrue(window.standardWindowButton(.zoomButton)?.isHidden == true)
        contentView.layoutSubtreeIfNeeded()
        let sliders = sliders(in: contentView)
        XCTAssertEqual(sliders.count, 2)
        for slider in sliders {
            XCTAssertEqual(slider.numberOfTickMarks, 9)
            XCTAssertTrue(slider.allowsTickMarkValuesOnly)
            XCTAssertFalse((slider.accessibilityLabel() ?? "").isEmpty)
            XCTAssertFalse((slider.accessibilityValue() as? String ?? "").isEmpty)
        }
    }

    func testSettingsPreviewResourcesFollowWindowVisibility() async {
        let suiteName = "OrbitTests.settings.lifecycle.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let viewModel = SpaceViewModel(
            colorAssignments: settings,
            previewSnapshot: SpaceSnapshot(
                identifiers: [11, 12, 13],
                activeIndex: 1
            )
        )
        let controller = SettingsWindowController(
            settings: settings,
            viewModel: viewModel
        )
        guard
            let window = controller.window,
            let contentView = window.contentView
        else {
            return XCTFail("Could not create settings window")
        }

        controller.show()
        let previewAppeared = await waitForView(
            SyncedIndicatorArtworkView.self,
            in: contentView,
            isPresent: true
        )
        XCTAssertTrue(previewAppeared)

        window.close()
        let previewDisappeared = await waitForView(
            SyncedIndicatorArtworkView.self,
            in: contentView,
            isPresent: false
        )
        XCTAssertTrue(previewDisappeared)

        controller.show()
        let previewReappeared = await waitForView(
            SyncedIndicatorArtworkView.self,
            in: contentView,
            isPresent: true
        )
        XCTAssertTrue(previewReappeared)
        controller.stop()
    }

    func testEnglishAndRussianCatalogsContainTheSameLocalizedKeys() throws {
        let requiredKeys: Set<String> = [
            "menu.settings",
            "menu.quit",
            "settings.window.title",
            "settings.section.appearance",
            "settings.section.behavior",
            "settings.demo.accessibility",
            "settings.animation.style",
            "settings.shape",
            "accessibility.status.desktop",
            "accessibility.status.fullscreen"
        ]
        var keysByLanguage: [String: Set<String>] = [:]

        for language in ["en", "ru"] {
            let localizationURL = try XCTUnwrap(
                Bundle.main.url(
                    forResource: language,
                    withExtension: "lproj"
                )
            )
            let stringsURL = localizationURL
                .appendingPathComponent("Localizable.strings")
            let data = try Data(contentsOf: stringsURL)
            let strings = try XCTUnwrap(
                PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as? [String: String]
            )
            XCTAssertTrue(requiredKeys.isSubset(of: Set(strings.keys)))
            XCTAssertGreaterThanOrEqual(strings.count, 63)
            XCTAssertTrue(strings.values.allSatisfy { !$0.isEmpty })
            keysByLanguage[language] = Set(strings.keys)
        }

        XCTAssertEqual(keysByLanguage["en"], keysByLanguage["ru"])
    }

    func testSizeAndSpacingUseIndependentDiscreteSteps() {
        XCTAssertEqual(AppSettings.indicatorSizeSteps.first, 0.9)
        XCTAssertEqual(AppSettings.indicatorSpacingSteps.first, 1)
        XCTAssertEqual(
            AppSettings.indicatorSpacingSteps.count,
            AppSettings.indicatorSizeSteps.count
        )
        XCTAssertEqual(AppSettings.normalizedIndicatorSize(0.94), 0.9)
        XCTAssertEqual(AppSettings.normalizedIndicatorSize(0.96), 1)
        XCTAssertEqual(AppSettings.normalizedIndicatorSpacing(0.9), 1)
        XCTAssertEqual(AppSettings.normalizedIndicatorSize(99), 1.7)
        XCTAssertEqual(
            AppSettings.normalizedIndicatorSpacing(99),
            1 + 8.0 / 12
        )
    }

    func testAnimationStyleDefaultsToSeamlessAndPersists() {
        withSettings { settings, defaults in
            XCTAssertEqual(settings.indicatorAnimationStyle, .seamless)

            settings.indicatorAnimationStyle = .classic

            let restored = AppSettings(defaults: defaults)
            XCTAssertEqual(restored.indicatorAnimationStyle, .classic)
            XCTAssertEqual(
                IndicatorAnimationStyle.allCases,
                [.classic, .seamless, .continuous]
            )
        }
    }

    func testShapeStyleDefaultsToStandardAndPersists() {
        withSettings { settings, defaults in
            XCTAssertEqual(settings.indicatorShapeStyle, .standard)

            settings.indicatorShapeStyle = .circles

            let restored = AppSettings(defaults: defaults)
            XCTAssertEqual(restored.indicatorShapeStyle, .circles)
            XCTAssertEqual(IndicatorShapeStyle.allCases.count, 3)
        }
    }

    func testThinOutlineDefaultsOffAndPersists() {
        withSettings { settings, defaults in
            XCTAssertFalse(settings.showsIndicatorOutline)

            settings.showsIndicatorOutline = true

            XCTAssertTrue(AppSettings(defaults: defaults).showsIndicatorOutline)
        }
    }

    func testMotionPresetsHonorReduceMotionAndAnimationSetting() {
        XCTAssertFalse(OrbitMotion.allowsMotion(
            userEnabled: true,
            reduceMotion: true
        ))
        XCTAssertFalse(OrbitMotion.allowsMotion(
            userEnabled: false,
            reduceMotion: false
        ))
        XCTAssertTrue(OrbitMotion.allowsMotion(
            userEnabled: true,
            reduceMotion: false
        ))
        XCTAssertNil(OrbitMotion.indicatorChange(
            style: .seamless,
            enabled: true,
            reduceMotion: true
        ))
        XCTAssertNil(OrbitMotion.hover(
            isHovered: true,
            enabled: false,
            reduceMotion: false
        ))
        XCTAssertNotNil(OrbitMotion.palette(
            enabled: true,
            reduceMotion: true
        ))
        XCTAssertNil(OrbitMotion.palette(
            enabled: false,
            reduceMotion: true
        ))
        XCTAssertNil(OrbitMotion.colorChange(
            enabled: false,
            reduceMotion: false
        ))
        XCTAssertNotNil(OrbitMotion.indicatorChange(
            style: .classic,
            enabled: true,
            reduceMotion: false
        ))
        XCTAssertNotNil(OrbitMotion.indicatorChange(
            style: .continuous,
            enabled: true,
            reduceMotion: false
        ))
        XCTAssertLessThanOrEqual(
            OrbitMotion.seamlessDuration,
            OrbitMotion.maximumFeedbackDuration
        )
        XCTAssertLessThanOrEqual(
            OrbitMotion.continuousDuration,
            OrbitMotion.maximumFeedbackDuration
        )
        XCTAssertLessThanOrEqual(
            OrbitMotion.hoverExitDuration,
            OrbitMotion.maximumFeedbackDuration
        )
        XCTAssertLessThanOrEqual(
            OrbitMotion.selectionChangeDuration,
            OrbitMotion.maximumFeedbackDuration
        )
        XCTAssertLessThan(
            OrbitMotion.reducedMotionFadeDuration,
            OrbitMotion.paletteDuration
        )
    }

    func testVisualSettingsChangesPublishSynchronouslyAfterMutation() {
        withSettings { settings, _ in
            var snapshots: [(
                change: VisualSettingsChange,
                size: Double,
                spacing: Double,
                animationsEnabled: Bool,
                style: IndicatorAnimationStyle,
                shape: IndicatorShapeStyle,
                outlineEnabled: Bool,
                colorCount: Int
            )] = []
            let cancellable = settings.visualSettingsChanges.sink { change in
                snapshots.append((
                    change,
                    settings.indicatorSizeScale,
                    settings.indicatorSpacingScale,
                    settings.animateIndicator,
                    settings.indicatorAnimationStyle,
                    settings.indicatorShapeStyle,
                    settings.showsIndicatorOutline,
                    settings.indicatorColors.count
                ))
            }

            settings.setIndicatorSizeScale(1.2)
            settings.setIndicatorSpacingScale(1.25)
            settings.setIndicatorColor(.systemRed, at: 0)
            settings.animateIndicator = false
            settings.indicatorAnimationStyle = .classic
            settings.indicatorShapeStyle = .roundedRectangles
            settings.showsIndicatorOutline = true

            XCTAssertEqual(snapshots.count, 7)
            XCTAssertEqual(snapshots[0].size, 1.2)
            XCTAssertEqual(snapshots[1].spacing, 1.25)
            XCTAssertEqual(snapshots[2].colorCount, 1)
            XCTAssertFalse(snapshots[3].animationsEnabled)
            XCTAssertEqual(snapshots[4].style, .classic)
            XCTAssertEqual(snapshots[5].shape, .roundedRectangles)
            XCTAssertTrue(snapshots[6].outlineEnabled)
            withExtendedLifetime(cancellable) {}
        }
    }

    func testColorsPersistAndReset() {
        withSettings { settings, defaults in
            settings.setIndicatorColor(.systemRed, at: 1)

            let restored = AppSettings(defaults: defaults)
            XCTAssertEqual(restored.indicatorColors.count, 2)
            assertSameRGB(restored.indicatorColors[1], .systemRed)

            restored.resetIndicatorColors()
            XCTAssertTrue(restored.indicatorColors.isEmpty)
        }
    }

    func testColorSlotsFollowSpaceIdentifiersAfterReordering() {
        withSettings { settings, defaults in
            XCTAssertEqual(
                settings.colorSlots(for: [101, 202, 303]),
                [101: 0, 202: 1, 303: 2]
            )
            XCTAssertEqual(
                settings.colorSlots(for: [303, 101, 202]),
                [101: 0, 202: 1, 303: 2]
            )

            let restored = AppSettings(defaults: defaults)
            XCTAssertEqual(
                restored.colorSlots(for: [202, 303, 101]),
                [101: 0, 202: 1, 303: 2]
            )
        }
    }

    func testDeletedSpaceColorIsNotReusedByNewSpace() {
        withSettings { settings, _ in
            _ = settings.colorSlots(for: [101, 202, 303])
            settings.setIndicatorColor(.systemRed, at: 0)
            settings.setIndicatorColor(.systemGreen, at: 1)
            settings.setIndicatorColor(.systemBlue, at: 2)

            XCTAssertEqual(
                settings.colorSlots(for: [101, 303]),
                [101: 0, 303: 1]
            )
            XCTAssertEqual(settings.indicatorColors.count, 2)
            assertSameRGB(settings.indicatorColors[1], .systemBlue)

            XCTAssertEqual(
                settings.colorSlots(for: [101, 303, 404]),
                [101: 0, 303: 1, 404: 2]
            )
            assertSameRGB(settings.indicatorColors[2], .controlAccentColor)
        }
    }

    private func withSettings(
        _ body: (AppSettings, UserDefaults) -> Void
    ) {
        let suiteName = "OrbitTests.settings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(AppSettings(defaults: defaults), defaults)
    }

    private func visualEffectView(in view: NSView) -> NSVisualEffectView? {
        if let visualEffect = view as? NSVisualEffectView {
            return visualEffect
        }
        return view.subviews.lazy.compactMap(visualEffectView).first
    }

    private func sliders(in view: NSView) -> [NSSlider] {
        let current = (view as? NSSlider).map { [$0] } ?? []
        return current + view.subviews.flatMap { sliders(in: $0) }
    }

    private func waitForView<ViewType: NSView>(
        _ type: ViewType.Type,
        in root: NSView,
        isPresent: Bool
    ) async -> Bool {
        for _ in 0..<50 {
            root.layoutSubtreeIfNeeded()
            if containsView(type, in: root) == isPresent {
                return true
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
        return containsView(type, in: root) == isPresent
    }

    private func containsView<ViewType: NSView>(
        _ type: ViewType.Type,
        in root: NSView
    ) -> Bool {
        root is ViewType
            || root.subviews.contains { containsView(type, in: $0) }
    }

    private func assertSameRGB(
        _ actual: NSColor,
        _ expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard
            let actual = actual.usingColorSpace(.sRGB),
            let expected = expected.usingColorSpace(.sRGB)
        else {
            return XCTFail("Could not convert colors", file: file, line: line)
        }
        XCTAssertEqual(
            actual.redComponent,
            expected.redComponent,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.greenComponent,
            expected.greenComponent,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.blueComponent,
            expected.blueComponent,
            accuracy: 0.001,
            file: file,
            line: line
        )
    }
}
