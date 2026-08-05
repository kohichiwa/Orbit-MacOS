import AppKit
import Combine
import QuartzCore
import SwiftUI

private enum SettingsWindowMetrics {
    static let contentSize = NSSize(width: 480, height: 640)
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let contentSize = SettingsWindowMetrics.contentSize
    private let presentationState: SettingsPresentationState
    private let onClose: ((SettingsWindowController) -> Void)?
    private var didNotifyClose = false

    init(
        settings: AppSettings,
        viewModel: SpaceViewModel,
        spaceApplicationReader: any SpaceApplicationReading =
            SystemSpaceApplicationReader(),
        onClose: ((SettingsWindowController) -> Void)? = nil
    ) {
        let presentationState = SettingsPresentationState()
        self.presentationState = presentationState
        self.onClose = onClose
        let rootView = SettingsRootView(
            settings: settings,
            viewModel: viewModel,
            spaceApplicationReader: spaceApplicationReader,
            presentationState: presentationState
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let backgroundView = SettingsWindowBackgroundView()
        backgroundView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
        ])

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = backgroundView
        window.title = OrbitL10n.text(
            "settings.window.title",
            fallback: "Настройки Orbit"
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.animationBehavior = .documentWindow
        window.contentMinSize = Self.contentSize
        window.contentMaxSize = Self.contentSize
        window.setContentSize(Self.contentSize)
        window.minSize = window.frame.size
        window.maxSize = window.frame.size
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        super.init(window: window)
        window.delegate = self
        window.setFrameAutosaveName("OrbitSettingsWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        didNotifyClose = false
        presentationState.isPresented = true
        if window.contentView?.bounds.size != Self.contentSize {
            window.setContentSize(Self.contentSize)
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    func stop() {
        presentationState.isPresented = false
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        presentationState.isPresented = false
        guard !didNotifyClose else { return }
        didNotifyClose = true
        onClose?(self)
    }
}

@MainActor
private final class SettingsPresentationState: ObservableObject {
    @Published var isPresented = false
}

private final class SettingsWindowBackgroundView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .followsWindowActiveState
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private struct SettingsRootView: View {
    @ObservedObject var settings: AppSettings
    let viewModel: SpaceViewModel
    let spaceApplicationReader: any SpaceApplicationReading
    @ObservedObject var presentationState: SettingsPresentationState

    var body: some View {
        ZStack {
            SettingsSurfaceBackground()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Group {
                    if presentationState.isPresented {
                        SettingsLiveDemo(
                            settings: settings,
                            viewModel: viewModel,
                            spaceApplicationReader: spaceApplicationReader
                        )
                    } else {
                        Color.clear
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: SettingsSurfaceMetrics.demoHeight)
                .ignoresSafeArea(.container, edges: .top)

                SettingsControls(settings: settings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(
            width: SettingsWindowMetrics.contentSize.width,
            height: SettingsWindowMetrics.contentSize.height
        )
        .background(Color.clear)
    }
}

@MainActor
private struct SettingsLiveDemo: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: SpaceViewModel
    let spaceApplicationReader: any SpaceApplicationReading

    private var colorSlotCount: Int {
        max(
            viewModel.indicatorKinds.map(\.colorIndex).max().map { $0 + 1 }
                ?? 1,
            1
        )
    }

    var body: some View {
        InteractiveDemoZone(
            indicators: viewModel.indicatorKinds,
            spaceIdentifiers: viewModel.indicators.map(\.id),
            currentActiveIndex: viewModel.activeIndex,
            colors: settings.indicatorColors(for: colorSlotCount),
            sizeScale: settings.indicatorSizeScale,
            spacingScale: settings.indicatorSpacingScale,
            shapeStyle: settings.indicatorShapeStyle,
            animationsEnabled: settings.animateIndicator,
            animationStyle: settings.indicatorAnimationStyle,
            showsApplicationsOnHover: settings.showsApplicationsOnHover,
            spaceApplicationReader: spaceApplicationReader,
            setColor: settings.setIndicatorColor
        )
    }
}

private enum SettingsSurfaceMetrics {
    static let demoHeight: CGFloat = 218
    static let transparentHeight: CGFloat = 180
    static let gradientHeight: CGFloat = 128
    static let demoSwipeBottomExtension = max(
        transparentHeight + gradientHeight - demoHeight,
        0
    )
}

private struct SettingsSurfaceBackground: View {
    private let opaqueBackground = Color(nsColor: .windowBackgroundColor)
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                opaqueBackground
            } else {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(
                            height: SettingsSurfaceMetrics.transparentHeight
                        )

                    LinearGradient(
                        colors: [
                            .clear,
                            opaqueBackground.opacity(0.025),
                            opaqueBackground.opacity(0.08),
                            opaqueBackground.opacity(0.17),
                            opaqueBackground.opacity(0.30),
                            opaqueBackground.opacity(0.47),
                            opaqueBackground.opacity(0.66),
                            opaqueBackground.opacity(0.83),
                            opaqueBackground
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: SettingsSurfaceMetrics.gradientHeight)

                    opaqueBackground
                }
            }
        }
        .ignoresSafeArea()
    }
}

@MainActor
private struct SettingsControls: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(
                title: OrbitL10n.text(
                    "settings.section.appearance",
                    fallback: "Оформление"
                ),
                symbol: "circle.lefthalf.filled"
            ) {
            } content: {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 20) {
                        DiscreteSliderColumn(
                            title: OrbitL10n.text(
                                "settings.size",
                                fallback: "Размер"
                            ),
                            value: Binding(
                                get: { settings.indicatorSizeScale },
                                set: { settings.setIndicatorSizeScale($0) }
                            ),
                            steps: AppSettings.indicatorSizeSteps
                        )

                        DiscreteSliderColumn(
                            title: OrbitL10n.text(
                                "settings.spacing",
                                fallback: "Расстояние"
                            ),
                            value: Binding(
                                get: { settings.indicatorSpacingScale },
                                set: { settings.setIndicatorSpacingScale($0) }
                            ),
                            steps: AppSettings.indicatorSpacingSteps
                        )
                    }
                    .padding(.bottom, 7)

                    ShapeStyleRow(
                        selection: $settings.indicatorShapeStyle
                    )
                }
            }

            SettingsSectionDivider()

            SettingsSection(
                title: OrbitL10n.text(
                    "settings.section.behavior",
                    fallback: "Поведение"
                ),
                symbol: "switch.2"
            ) {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: OrbitL10n.text(
                            "settings.animation.enabled",
                            fallback: "Анимация"
                        ),
                        isOn: $settings.animateIndicator
                    )

                    AnimationStyleRow(
                        selection: $settings.indicatorAnimationStyle,
                        isEnabled: settings.animateIndicator
                    )

                    SettingsToggleRow(
                        title: OrbitL10n.text(
                            "settings.applicationsOnHover",
                            fallback: "Приложения при наведении"
                        ),
                        isOn: $settings.showsApplicationsOnHover
                    )

                    SettingsToggleRow(
                        title: OrbitL10n.text(
                            "settings.launchAtLogin",
                            fallback: "Запускать при входе…"
                        ),
                        statusText: settings.launchAtLoginState == .mixed
                            ? OrbitL10n.text(
                                "settings.launchAtLogin.requiresApproval",
                                fallback: "Требует подтверждения"
                            )
                            : nil,
                        isOn: Binding(
                            get: { settings.launchAtLoginState == .on },
                            set: { _ in settings.toggleLaunchAtLogin() }
                        )
                    )
                }
            }

            if let message = settings.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, SettingsGridMetrics.windowHorizontalInset)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

private struct SettingsSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.vertical, 2)
            .accessibilityHidden(true)
    }
}

private enum SettingsGridMetrics {
    static let windowHorizontalInset: CGFloat = 24
    static let labelWidth: CGFloat = 124
    static let columnSpacing: CGFloat = 14
    static let segmentedControlWidth: CGFloat = 270
}

private struct SettingsSection<Trailing: View, Content: View>: View {
    let title: String
    let symbol: String
    let trailing: Trailing
    let content: Content

    init(
        title: String,
        symbol: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SettingsSectionTitle(title: title, symbol: symbol)
                Spacer(minLength: 8)
                trailing
            }

            content
        }
    }
}

private extension SettingsSection where Trailing == EmptyView {
    init(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            symbol: symbol,
            trailing: { EmptyView() },
            content: content
        )
    }
}

private struct SettingsRowLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(
                width: SettingsGridMetrics.labelWidth,
                alignment: .leading
            )
    }
}

private struct SettingsSectionTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 17, alignment: .center)
            Text(title)
                .font(.headline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    var statusText: String?
    @Binding var isOn: Bool

    init(
        title: String,
        statusText: String? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.statusText = statusText
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: SettingsGridMetrics.columnSpacing) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
        .frame(height: 34)
    }
}

private struct AnimationStyleRow: View {
    @Binding var selection: IndicatorAnimationStyle
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: SettingsGridMetrics.columnSpacing) {
            SettingsRowLabel(
                title: OrbitL10n.text(
                    "settings.animation.style",
                    fallback: "Стиль"
                )
            )
            AnimationStyleSelector(
                selection: $selection,
                isEnabled: isEnabled
            )
            .frame(
                width: SettingsGridMetrics.segmentedControlWidth,
                alignment: .trailing
            )
        }
        .frame(height: 36)
    }
}

private struct ShapeStyleRow: View {
    @Binding var selection: IndicatorShapeStyle

    var body: some View {
        HStack(spacing: SettingsGridMetrics.columnSpacing) {
            SettingsRowLabel(
                title: OrbitL10n.text(
                    "settings.shape",
                    fallback: "Форма"
                )
            )
            ShapeStyleSelector(selection: $selection)
                .frame(
                    width: SettingsGridMetrics.segmentedControlWidth,
                    alignment: .trailing
                )
        }
        .frame(height: 36)
    }
}

private struct ShapeStyleSelector: View {
    @Binding var selection: IndicatorShapeStyle

    var body: some View {
        Picker(
            OrbitL10n.text(
                "settings.shape.accessibility",
                fallback: "Форма индикаторов"
            ),
            selection: $selection
        ) {
            ForEach(IndicatorShapeStyle.allCases) { style in
                Text(style.title)
                    .tag(style)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.regular)
        .accessibilityLabel(
            OrbitL10n.text(
                "settings.shape.accessibility",
                fallback: "Форма индикаторов"
            )
        )
        .accessibilityValue(selection.title)
    }

}

private struct AnimationStyleSelector: View {
    @Binding var selection: IndicatorAnimationStyle
    let isEnabled: Bool

    var body: some View {
        Picker(
            OrbitL10n.text(
                "settings.animation.style.accessibility",
                fallback: "Стиль анимации"
            ),
            selection: $selection
        ) {
            ForEach(IndicatorAnimationStyle.allCases) { style in
                Text(style.title)
                    .tag(style)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.regular)
        .accessibilityLabel(
            OrbitL10n.text(
                "settings.animation.style.accessibility",
                fallback: "Стиль анимации"
            )
        )
        .accessibilityValue(selection.title)
        .disabled(!isEnabled)
    }

}

private struct DemoVisualConfiguration: Equatable {
    let sizeScale: Double
    let spacingScale: Double
    let shapeStyle: IndicatorShapeStyle
    let animationsEnabled: Bool
    let animationStyle: IndicatorAnimationStyle
    let increasedContrast: Bool
}

private struct DemoApplicationPreviewRequest: Equatable {
    let index: Int
    let spaceIdentifier: Int64
    let isFullscreen: Bool
}

private enum DemoOverlay: Equatable {
    case color(spaceIdentifier: Int64)
}

private struct InteractiveDemoZone: View {
    private static let maximumArtworkWidth =
        StatusApplicationPreviewLayout.demoMaximumContentWidth
    private static let paletteGap: CGFloat = 20

    let indicators: [SpaceIndicatorKind]
    let spaceIdentifiers: [Int64]
    let currentActiveIndex: Int?
    let colors: [NSColor]
    let sizeScale: Double
    let spacingScale: Double
    let shapeStyle: IndicatorShapeStyle
    let animationsEnabled: Bool
    let animationStyle: IndicatorAnimationStyle
    let showsApplicationsOnHover: Bool
    let spaceApplicationReader: any SpaceApplicationReading
    let setColor: (NSColor, Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var activeIndex = 0
    @State private var hoveredIndex: Int?
    @State private var overlay: DemoOverlay?
    @State private var glowIsVisible = false
    @State private var applicationPreviewIndex: Int?
    @State private var applicationPreviewApplications: [
        SpaceApplicationPresentation
    ] = []
    @State private var isApplicationPreviewPresented = false
    @State private var applicationPreviewFallbackIndex: Int?
    @State private var applicationPreviewSuppressedIndex: Int?
    @State private var renderedIndicatorOffsets: [CGFloat] = []

    private var previewColors: [NSColor] {
        colors.isEmpty
            ? Array(repeating: .controlAccentColor, count: 3)
            : colors
    }

    var body: some View {
        ZStack {
            IndicatorGlow(
                target: activeGlowTarget,
                visibility: glowIsVisible ? 1 : 0
            )
            .animation(glowAnimation, value: activeGlowTarget)
            .animation(glowAnimation, value: glowIsVisible)
            .allowsHitTesting(false)

            if !indicators.isEmpty {
                ZStack {
                    DemoIndicatorArtwork(
                        indicators: indicators,
                        colors: previewColors,
                        activeIndex: activeIndex,
                        hoveredIndex: artworkHoveredIndex,
                        sizeScale: demoScale,
                        spacingScale: CGFloat(configuration.spacingScale),
                        shapeStyle: configuration.shapeStyle,
                        animationsEnabled: configuration.animationsEnabled,
                        animationStyle: configuration.animationStyle,
                        reduceMotion: reduceMotion,
                        increasedContrast: configuration.increasedContrast,
                        applicationPreviewIndex: applicationPreviewIndex,
                        applicationPreviewApplications:
                            applicationPreviewApplications,
                        isApplicationPreviewPresented:
                            isApplicationPreviewPresented,
                        onApplicationPreviewDismissed: {
                            completeApplicationPreviewDismissal()
                        },
                        onRenderedIndicatorOffsets: { offsets in
                            renderedIndicatorOffsets = offsets
                        }
                    )

                    HStack(spacing: 0) {
                        ForEach(indicators.indices, id: \.self) { index in
                            Color.clear
                                .frame(
                                    width: demoInteractionWidth(for: index),
                                    height: demoArtworkHeight
                                )
                                .contentShape(Rectangle())
                                .overlay {
                                    PrimarySecondaryClickTarget(
                                        accessibilityLabel:
                                            indicatorAccessibilityLabel(
                                                for: index
                                            ),
                                        accessibilityValue:
                                            indicatorAccessibilityValue(
                                                for: index
                                            ),
                                        accessibilityHelp:
                                            indicatorAccessibilityHelp(
                                                for: index
                                            ),
                                        accessibilityIdentifier:
                                            "orbit.demo.indicator.\(index)",
                                        isSelected: activeIndex == index,
                                        action: {
                                            select(index)
                                        },
                                        onHover: { hovering in
                                            if hovering {
                                                if hoveredIndex != index {
                                                    applicationPreviewSuppressedIndex =
                                                        nil
                                                }
                                                hoveredIndex = index
                                                applicationPreviewFallbackIndex =
                                                    nil
                                            } else if hoveredIndex == index {
                                                hoveredIndex = nil
                                                if
                                                    applicationPreviewSuppressedIndex
                                                        == index
                                                {
                                                    applicationPreviewSuppressedIndex =
                                                        nil
                                                }
                                            }
                                        }
                                    )
                                }
                                .popupClickProtected()
                        }
                    }
                }
                .frame(
                    width: demoArtworkWidth,
                    height: demoArtworkHeight
                )
                .offset(y: 26)
            }

            GeometryReader { proxy in
                if let paletteIndex {
                    let placement = demoPalettePlacement(
                        for: paletteIndex,
                        containerWidth: proxy.size.width,
                    )

                    IndicatorColorPalette(
                        selectedColorID: PaletteColor.matchingID(
                            for: color(for: indicators[paletteIndex])
                        ),
                        horizontalOffset:
                            placement.bubbleCenterOffset,
                        verticalOffset: paletteCenterY(
                            in: proxy.size.height
                        ) - proxy.size.height / 2,
                        pointerOffset: placement.pointerOffset,
                        selectColor: {
                            [
                                spaceIdentifier =
                                    spaceIdentifiers[paletteIndex]
                            ] paletteColor in
                            applyColor(
                                paletteColor,
                                to: spaceIdentifier
                            )
                        }
                    )
                    // Keep one palette instance while switching indicators so
                    // SwiftUI animates its anchor instead of removing and
                    // inserting the whole popup.
                    .id("indicator-color-palette")
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height / 2
                    )
                    .popupClickProtected()
                    .transition(paletteTransition)
                    .animation(
                        paletteAnimation,
                        value: paletteIndex
                    )
                    .animation(
                        paletteAnimation,
                        value: isApplicationPreviewPresented
                    )
                }
            }
            .animation(paletteAnimation, value: overlay)
            .zIndex(20)

            TrackpadSwipeMonitor(
                bottomExtension:
                    SettingsSurfaceMetrics.demoSwipeBottomExtension
            ) { direction in
                moveActive(by: direction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            OrbitL10n.text(
                "settings.demo.accessibility",
                fallback: "Интерактивная демонстрация индикаторов"
            )
        )
        .accessibilityAction(
            named: OrbitL10n.text(
                "settings.demo.previous.accessibility",
                fallback: "Предыдущее пространство"
            )
        ) {
            moveActive(by: -1)
        }
        .accessibilityAction(
            named: OrbitL10n.text(
                "settings.demo.next.accessibility",
                fallback: "Следующее пространство"
            )
        ) {
            moveActive(by: 1)
        }
        .onExitCommand(perform: dismissPopups)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard
                        abs(value.translation.width)
                            > abs(value.translation.height)
                    else { return }
                    moveActive(by: value.translation.width < 0 ? 1 : -1)
                }
        )
        .onAppear {
            synchronizeActiveIndex()
            showGlow()
        }
        .onChange(of: requestedConfiguration) {
            dismissOverlay()
        }
        .onChange(of: currentActiveIndex) { synchronizeActiveIndex() }
        .onChange(of: spaceIdentifiers) {
            validateOverlaySpace()
        }
        .task(id: applicationPreviewRequest) {
            let presentationNotBefore: TimeInterval
            presentationNotBefore = CACurrentMediaTime()
                + OrbitMotion.applicationPreviewHoverDelay
            isApplicationPreviewPresented = false
            applicationPreviewFallbackIndex = nil
            guard let request = applicationPreviewRequest else {
                if applicationPreviewIndex == nil {
                    applicationPreviewApplications.removeAll()
                }
                return
            }

            let initialDelay = presentationNotBefore
                - CACurrentMediaTime()
            if initialDelay > 0 {
                try? await Task.sleep(
                    for: .seconds(initialDelay)
                )
            }

            while !Task.isCancelled {
                guard applicationPreviewRequest == request else { return }
                let processIdentifiers =
                    await spaceApplicationReader
                        .applicationProcessIdentifiers(
                            in: request.spaceIdentifier
                        )
                guard
                    !Task.isCancelled,
                    applicationPreviewRequest == request
                else { return }
                let presentations =
                    SpaceApplicationPresentationFactory.presentations(
                        for: processIdentifiers,
                        maximumCount: request.isFullscreen
                            ? 1
                            : StatusApplicationPreviewLayout.maximumIconCount,
                        iconResolution: .demo
                    )
                guard !presentations.isEmpty else {
                    isApplicationPreviewPresented = false
                    applicationPreviewFallbackIndex = request.index
                    if applicationPreviewIndex == nil {
                        applicationPreviewApplications.removeAll()
                    }
                    return
                }
                applicationPreviewFallbackIndex = nil
                applicationPreviewIndex = request.index
                applicationPreviewApplications = presentations
                isApplicationPreviewPresented = true

                try? await Task.sleep(
                    for: .seconds(
                        OrbitMotion.applicationPreviewRefreshInterval
                    )
                )
            }
        }
        .onChange(of: indicators.count) {
            guard !indicators.isEmpty else {
                activeIndex = 0
                dismissOverlay()
                hoveredIndex = nil
                isApplicationPreviewPresented = false
                applicationPreviewSuppressedIndex = nil
                return
            }
            activeIndex = min(activeIndex, indicators.count - 1)
            if let hoveredIndex,
               !indicators.indices.contains(hoveredIndex) {
                self.hoveredIndex = nil
                isApplicationPreviewPresented = false
            }
        }
        .overlayPreferenceValue(PopupClickProtectedKey.self) { anchors in
            GeometryReader { proxy in
                PopupOutsideClickMonitor(
                    isPresented: overlay != nil,
                    protectedRects: anchors.map { proxy[$0] },
                    dismiss: dismissPopups
                )
                .allowsHitTesting(false)
            }
        }
    }

    private var demoScale: CGFloat {
        let requestedScale = CGFloat(configuration.sizeScale) * (2.15 / 1.2)
        return StatusItemArtwork.fittedSizeScale(
            for: indicators.count,
            requestedSizeScale: requestedScale,
            spacingScale: CGFloat(configuration.spacingScale),
            maximumWidth: Self.maximumArtworkWidth
        )
    }

    private var artworkHoveredIndex: Int? {
        guard showsApplicationsOnHover else { return hoveredIndex }
        return applicationPreviewFallbackIndex == hoveredIndex
            ? hoveredIndex
            : nil
    }

    private var applicationPreviewRequest:
        DemoApplicationPreviewRequest? {
        guard
            showsApplicationsOnHover,
            let hoveredIndex,
            applicationPreviewSuppressedIndex != hoveredIndex,
            indicators.indices.contains(hoveredIndex),
            spaceIdentifiers.indices.contains(hoveredIndex)
        else { return nil }
        return DemoApplicationPreviewRequest(
            index: hoveredIndex,
            spaceIdentifier: spaceIdentifiers[hoveredIndex],
            isFullscreen: indicators[hoveredIndex].isFullscreen
        )
    }

    private var demoItemWidth: CGFloat {
        StatusItemArtwork.itemWidth(
            sizeScale: demoScale,
            spacingScale: CGFloat(configuration.spacingScale)
        )
    }

    private var demoPreviewExtraWidth: CGFloat {
        guard
            isApplicationPreviewPresented,
            let applicationPreviewIndex,
            indicators.indices.contains(applicationPreviewIndex),
            !applicationPreviewApplications.isEmpty
        else { return 0 }

        let targetWidth = StatusApplicationPreviewLayout.targetSize(
            iconCount: applicationPreviewApplications.count,
            scale: demoScale
        ).width
        let baseWidth = StatusItemArtwork.dotDiameter(
            sizeScale: demoScale
        )
        return max(targetWidth - baseWidth, 0)
    }

    private var demoPreviewContentScale: CGFloat {
        guard demoPreviewExtraWidth > 0 else { return 1 }
        let contentWidth = StatusItemArtwork.contentWidth(
            for: indicators.count,
            sizeScale: demoScale,
            spacingScale: CGFloat(configuration.spacingScale)
        )
        let outerPadding = StatusItemArtwork.horizontalPadding(
            sizeScale: demoScale
        ) * 2
        return min(
            max(Self.maximumArtworkWidth - outerPadding, 0.01)
                / max(contentWidth + demoPreviewExtraWidth, 0.01),
            1
        )
    }

    private func demoInteractionWidth(for index: Int) -> CGFloat {
        let extraWidth = index == applicationPreviewIndex
            ? demoPreviewExtraWidth
            : 0
        return (demoItemWidth + extraWidth) * demoPreviewContentScale
    }

    private var demoArtworkWidth: CGFloat {
        Self.maximumArtworkWidth
    }

    private var demoArtworkHeight: CGFloat {
        SyncedIndicatorArtworkView.previewHeight(for: demoScale)
    }

    private var paletteArtworkHeight: CGFloat {
        isApplicationPreviewPresented
            ? demoArtworkHeight
            : StatusItemArtwork.dotDiameter(sizeScale: demoScale)
    }

    private var glowAnimation: Animation? {
        OrbitMotion.indicatorChange(
            style: configuration.animationStyle,
            enabled: configuration.animationsEnabled,
            reduceMotion: reduceMotion
        )
    }

    private var paletteAnimation: Animation? {
        OrbitMotion.palette(
            enabled: configuration.animationsEnabled,
            reduceMotion: reduceMotion
        )
    }

    private var paletteTransition: AnyTransition {
        reduceMotion ? .opacity : .liquidPalette
    }

    private var requestedConfiguration: DemoVisualConfiguration {
        DemoVisualConfiguration(
            sizeScale: sizeScale,
            spacingScale: spacingScale,
            shapeStyle: shapeStyle,
            animationsEnabled: animationsEnabled,
            animationStyle: animationStyle,
            increasedContrast: colorSchemeContrast == .increased
        )
    }

    private var configuration: DemoVisualConfiguration {
        requestedConfiguration
    }

    private var activeGlowColor: NSColor {
        guard indicators.indices.contains(activeIndex) else {
            return .controlAccentColor
        }
        return color(for: indicators[activeIndex])
    }

    private var activeGlowHorizontalOffset: CGFloat {
        guard indicators.indices.contains(activeIndex) else { return 0 }
        return demoIndicatorHorizontalOffset(for: activeIndex)
    }

    private var activeGlowTarget: IndicatorGlowTarget {
        IndicatorGlowTarget(
            color: activeGlowColor,
            horizontalOffset: activeGlowHorizontalOffset
        )
    }

    private func color(for kind: SpaceIndicatorKind) -> NSColor {
        previewColors.indices.contains(kind.colorIndex)
            ? previewColors[kind.colorIndex]
            : .controlAccentColor
    }

    private func select(_ index: Int) {
        guard
            indicators.indices.contains(index),
            spaceIdentifiers.indices.contains(index)
        else { return }
        let spaceIdentifier = spaceIdentifiers[index]
        let colorOverlay = DemoOverlay.color(
            spaceIdentifier: spaceIdentifier
        )
        guard overlay != colorOverlay else {
            dismissOverlay()
            return
        }

        overlay = colorOverlay
    }

    private var paletteIndex: Int? {
        guard case let .color(spaceIdentifier) = overlay else {
            return nil
        }
        return spaceIdentifiers.firstIndex(of: spaceIdentifier).flatMap {
            indicators.indices.contains($0) ? $0 : nil
        }
    }

    private func demoIndicatorHorizontalOffset(for index: Int) -> CGFloat {
        guard indicators.indices.contains(index) else { return 0 }
        if renderedIndicatorOffsets.indices.contains(index) {
            return renderedIndicatorOffsets[index]
        }
        let widths = indicators.indices.map(demoInteractionWidth)
        let totalWidth = widths.reduce(0, +)
        let precedingWidth = widths.prefix(index).reduce(0, +)
        return -totalWidth / 2
            + precedingWidth
            + widths[index] / 2
    }

    private func paletteCenterY(in containerHeight: CGFloat) -> CGFloat {
        let paletteGap: CGFloat = Self.paletteGap
        let artworkCenterY = containerHeight / 2 + 26
        return artworkCenterY
            - paletteArtworkHeight / 2
            - IndicatorColorPalette.totalHeight / 2
            - paletteGap
    }

    private func applyColor(
        _ paletteColor: PaletteColor,
        to spaceIdentifier: Int64
    ) {
        guard
            let currentIndex = spaceIdentifiers.firstIndex(
                of: spaceIdentifier
            ),
            indicators.indices.contains(currentIndex)
        else { return }
        setColor(
            paletteColor.color,
            indicators[currentIndex].colorIndex
        )
    }

    private func demoPalettePlacement(
        for index: Int,
        containerWidth: CGFloat
    ) -> PopupHorizontalPlacement {
        let anchorOffset = demoIndicatorHorizontalOffset(for: index)
        return PopupHorizontalPlacement.resolve(
            anchorOffset: anchorOffset,
            containerWidth: containerWidth,
            bubbleWidth: IndicatorColorPalette.width,
            horizontalInset: SettingsGridMetrics.windowHorizontalInset,
            pointerEdgeInset:
                IndicatorColorPalette.pointerEdgeInset
        )
    }

    private func moveActive(by offset: Int) {
        guard !indicators.isEmpty else { return }
        let destination = activeIndex + offset
        guard indicators.indices.contains(destination) else { return }
        suppressApplicationPreviewDuringSpaceTransition()
        dismissOverlay()
        activeIndex = destination
    }

    private func suppressApplicationPreviewDuringSpaceTransition() {
        guard
            applicationPreviewIndex != nil
                || isApplicationPreviewPresented
        else { return }
        isApplicationPreviewPresented = false
        applicationPreviewFallbackIndex = nil
        applicationPreviewSuppressedIndex = hoveredIndex
    }

    private func indicatorAccessibilityLabel(for index: Int) -> String {
        switch indicators[index] {
        case .desktop:
            let desktopOrdinal = indicators.prefix(index + 1)
                .filter { !$0.isFullscreen }
                .count
            return OrbitL10n.format(
                "settings.demo.desktop.accessibility",
                fallback: "Рабочий стол %ld",
                desktopOrdinal
            )
        case .fullscreen:
            return OrbitL10n.text(
                "settings.demo.fullscreen.accessibility",
                fallback: "Полноэкранное приложение"
            )
        }
    }

    private func indicatorAccessibilityValue(for index: Int) -> String {
        activeIndex == index
            ? OrbitL10n.text(
                "accessibility.state.current",
                fallback: "Текущее"
            )
            : OrbitL10n.text(
                "accessibility.state.inactive",
                fallback: "Неактивное"
            )
    }

    private func indicatorAccessibilityHelp(for index: Int) -> String {
        if indicators[index].isFullscreen {
            return OrbitL10n.text(
                "settings.demo.fullscreen.help",
                fallback: "Изменяет цвет связанного рабочего стола"
            )
        }
        return OrbitL10n.text(
            "settings.demo.desktop.help",
            fallback: "Изменяет цвет индикатора"
        )
    }

    private func dismissPopups() {
        dismissOverlay()
    }

    private func dismissOverlay() {
        overlay = nil
    }

    private func completeApplicationPreviewDismissal() {
        guard !isApplicationPreviewPresented else { return }
        if let request = applicationPreviewRequest,
           applicationPreviewFallbackIndex != request.index {
            return
        }
        applicationPreviewIndex = nil
        applicationPreviewApplications.removeAll()
    }

    private func validateOverlaySpace() {
        if case let .color(spaceIdentifier) = overlay,
           !spaceIdentifiers.contains(spaceIdentifier) {
            dismissOverlay()
            return
        }
    }

    private func synchronizeActiveIndex() {
        guard
            let currentActiveIndex,
            indicators.indices.contains(currentActiveIndex)
        else { return }
        guard activeIndex != currentActiveIndex else { return }
        suppressApplicationPreviewDuringSpaceTransition()
        activeIndex = currentActiveIndex
    }

    private func showGlow() {
        guard !glowIsVisible else { return }
        DispatchQueue.main.async {
            withAnimation(glowAnimation) {
                glowIsVisible = true
            }
        }
    }

}

private struct IndicatorGlowTarget: Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat
    var horizontalOffset: CGFloat

    init(color: NSColor, horizontalOffset: CGFloat) {
        let resolvedColor = color.usingColorSpace(.extendedSRGB)
            ?? NSColor.controlAccentColor.usingColorSpace(.extendedSRGB)!
        red = resolvedColor.redComponent
        green = resolvedColor.greenComponent
        blue = resolvedColor.blueComponent
        alpha = resolvedColor.alphaComponent
        self.horizontalOffset = horizontalOffset
    }
}

private struct IndicatorGlow: View, Animatable {
    var target: IndicatorGlowTarget
    var visibility: CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<
            AnimatablePair<CGFloat, CGFloat>,
            AnimatablePair<CGFloat, CGFloat>
        >
    > {
        get {
            AnimatablePair(
                AnimatablePair(target.red, target.green),
                AnimatablePair(
                    AnimatablePair(target.blue, target.alpha),
                    AnimatablePair(target.horizontalOffset, visibility)
                )
            )
        }
        set {
            target.red = newValue.first.first
            target.green = newValue.first.second
            target.blue = newValue.second.first.first
            target.alpha = newValue.second.first.second
            target.horizontalOffset = newValue.second.second.first
            visibility = newValue.second.second.second
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let visibleAmount = min(max(visibility, 0), 1)
            let glowColor = Color(
                .sRGB,
                red: Double(target.red),
                green: Double(target.green),
                blue: Double(target.blue),
                opacity: Double(target.alpha)
            )

            RadialGradient(
                colors: [
                    glowColor.opacity(0.22),
                    glowColor.opacity(0.09),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 254 + 56 * visibleAmount
            )
            .frame(width: 620, height: 620)
            .blur(radius: 22 - 4 * visibleAmount)
            .opacity(visibleAmount)
            .position(
                x: proxy.size.width / 2 + target.horizontalOffset,
                y: proxy.size.height / 2 + 26
            )
        }
    }
}

private struct PaletteColor: Identifiable {
    let id: String
    let title: String
    let color: NSColor

    static let choices: [PaletteColor] = [
        PaletteColor(
            id: "red",
            title: OrbitL10n.text("color.red", fallback: "Красный"),
            color: .systemRed
        ),
        PaletteColor(
            id: "orange",
            title: OrbitL10n.text("color.orange", fallback: "Оранжевый"),
            color: .systemOrange
        ),
        PaletteColor(
            id: "yellow",
            title: OrbitL10n.text("color.yellow", fallback: "Жёлтый"),
            color: .systemYellow
        ),
        PaletteColor(
            id: "green",
            title: OrbitL10n.text("color.green", fallback: "Зелёный"),
            color: .systemGreen
        ),
        PaletteColor(
            id: "blue",
            title: OrbitL10n.text("color.blue", fallback: "Синий"),
            color: .systemBlue
        ),
        PaletteColor(
            id: "purple",
            title: OrbitL10n.text("color.purple", fallback: "Фиолетовый"),
            color: .systemPurple
        )
    ]

    static func matchingID(for color: NSColor) -> String? {
        guard let selected = color.usingColorSpace(.sRGB) else { return nil }
        let match = choices.min { lhs, rhs in
            colorDistance(from: selected, to: lhs.color)
                < colorDistance(from: selected, to: rhs.color)
        }
        guard let match,
              colorDistance(from: selected, to: match.color) < 0.12
        else { return nil }
        return match.id
    }

    private static func colorDistance(
        from selected: NSColor,
        to candidate: NSColor
    ) -> CGFloat {
        guard let candidate = candidate.usingColorSpace(.sRGB) else {
            return .greatestFiniteMagnitude
        }
        let red = selected.redComponent - candidate.redComponent
        let green = selected.greenComponent - candidate.greenComponent
        let blue = selected.blueComponent - candidate.blueComponent
        return sqrt(red * red + green * green + blue * blue)
    }
}

private struct IndicatorColorPalette: View, Animatable {
    static let bodyHeight: CGFloat = 41
    static let pointerHeight: CGFloat = 8
    static let totalHeight = bodyHeight + pointerHeight
    static let width: CGFloat = 224
    static let pointerEdgeInset: CGFloat = 29

    let selectedColorID: String?
    var horizontalOffset: CGFloat
    var verticalOffset: CGFloat
    var pointerOffset: CGFloat
    let selectColor: (PaletteColor) -> Void
    private var selectedColorOffset: CGFloat

    init(
        selectedColorID: String?,
        horizontalOffset: CGFloat,
        verticalOffset: CGFloat,
        pointerOffset: CGFloat,
        selectColor: @escaping (PaletteColor) -> Void
    ) {
        self.selectedColorID = selectedColorID
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
        self.pointerOffset = pointerOffset
        self.selectColor = selectColor
        selectedColorOffset = Self.colorOffset(
            for: selectedColorID
        )
    }

    var animatableData:
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get {
            AnimatablePair(
                AnimatablePair(horizontalOffset, verticalOffset),
                pointerOffset
            )
        }
        set {
            horizontalOffset = newValue.first.first
            verticalOffset = newValue.first.second
            pointerOffset = newValue.second
        }
    }

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(PaletteColor.choices) { choice in
                    Button {
                        selectColor(choice)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(nsColor: choice.color))
                                .frame(width: 16.5, height: 16.5)
                            Circle()
                                .strokeBorder(
                                    Color.white.opacity(0.32),
                                    lineWidth: 0.7
                                )
                                .frame(width: 16.5, height: 16.5)
                        }
                        .frame(width: 26.5, height: 26.5)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.title)
                    .accessibilityValue(
                        choice.id == selectedColorID
                            ? OrbitL10n.text(
                                "accessibility.state.selected",
                                fallback: "Выбран"
                            )
                            : OrbitL10n.text(
                                "accessibility.state.notSelected",
                                fallback: "Не выбран"
                            )
                    )
                    .accessibilityAddTraits(
                        choice.id == selectedColorID ? .isSelected : []
                    )
                }
            }

            Canvas { context, size in
                guard selectedColorID != nil else { return }
                let ringSize: CGFloat = 22.5
                let ringRect = CGRect(
                    x: size.width / 2 - ringSize / 2
                        + selectedColorOffset,
                    y: size.height / 2 - ringSize / 2,
                    width: ringSize,
                    height: ringSize
                )
                context.stroke(
                    Path(ellipseIn: ringRect),
                    with: .color(Color.primary.opacity(0.76)),
                    lineWidth: 1.5
                )
            }
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 8)
        .frame(width: Self.width, height: Self.bodyHeight)
        .padding(.bottom, Self.pointerHeight)
        .stableBubbleSurface(
            PaletteBubbleShape(pointerOffset: pointerOffset)
        )
        .fixedSize(horizontal: true, vertical: true)
        .compositingGroup()
        .offset(x: horizontalOffset, y: verticalOffset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            OrbitL10n.text(
                "settings.demo.colorPicker.accessibility",
                fallback: "Цвет индикатора"
            )
        )
        .accessibilityIdentifier("orbit.demo.colorPicker")
    }

    private static func colorOffset(
        for selectedColorID: String?
    ) -> CGFloat {
        guard
            let selectedColorID,
            let index = PaletteColor.choices.firstIndex(
                where: { $0.id == selectedColorID }
            )
        else { return 0 }
        let itemStep: CGFloat = 26.5 + 8
        let centeredIndex = CGFloat(index)
            - CGFloat(PaletteColor.choices.count - 1) / 2
        return centeredIndex * itemStep
    }
}

private struct StableBubbleSurface<Surface: Shape>: ViewModifier {
    let surface: Surface
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: surface)
            .overlay {
                surface
                    .stroke(
                        Color.primary.opacity(
                            colorSchemeContrast == .increased ? 0.30 : 0.13
                        ),
                        style: StrokeStyle(
                            lineWidth: 1,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .allowsHitTesting(false)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }
}

private extension View {
    func stableBubbleSurface<Surface: Shape>(
        _ surface: Surface
    ) -> some View {
        modifier(StableBubbleSurface(surface: surface))
    }
}

private struct LiquidPaletteModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                x: 0.96 + progress * 0.04,
                y: 0.88 + progress * 0.12,
                anchor: .bottom
            )
            .offset(y: (1 - progress) * 8)
            .opacity(progress)
    }
}

extension AnyTransition {
    fileprivate static var liquidPalette: AnyTransition {
        .modifier(
            active: LiquidPaletteModifier(progress: 0),
            identity: LiquidPaletteModifier(progress: 1)
        )
    }
}

private struct PaletteBubbleShape: Shape {
    var pointerOffset: CGFloat

    func path(in rect: CGRect) -> Path {
        let pointerHeight: CGFloat = 9
        let bodyHeight = rect.height - pointerHeight
        let radius = bodyHeight / 2
        let curve: CGFloat = 0.552_284_8
        let pointerHalfWidth: CGFloat = 9
        let pointerCenterX = min(
            max(
                rect.midX + pointerOffset,
                rect.minX + radius + pointerHalfWidth
            ),
            rect.maxX - radius - pointerHalfWidth
        )
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(
            to: CGPoint(x: rect.maxX - radius, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY + radius
            ),
            control1: CGPoint(
                x: rect.maxX - radius + curve * radius,
                y: rect.minY
            ),
            control2: CGPoint(
                x: rect.maxX,
                y: rect.minY + radius - curve * radius
            )
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - radius, y: bodyHeight),
            control1: CGPoint(
                x: rect.maxX,
                y: rect.minY + radius + curve * radius
            ),
            control2: CGPoint(
                x: rect.maxX - radius + curve * radius,
                y: bodyHeight
            )
        )
        path.addLine(
            to: CGPoint(x: pointerCenterX + pointerHalfWidth, y: bodyHeight)
        )
        path.addCurve(
            to: CGPoint(x: pointerCenterX + 1.6, y: rect.maxY - 1.2),
            control1: CGPoint(
                x: pointerCenterX + 5.5,
                y: bodyHeight + 0.2
            ),
            control2: CGPoint(
                x: pointerCenterX + 3.2,
                y: rect.maxY - 1.8
            )
        )
        path.addQuadCurve(
            to: CGPoint(x: pointerCenterX - 1.6, y: rect.maxY - 1.2),
            control: CGPoint(x: pointerCenterX, y: rect.maxY + 0.5)
        )
        path.addCurve(
            to: CGPoint(
                x: pointerCenterX - pointerHalfWidth,
                y: bodyHeight
            ),
            control1: CGPoint(
                x: pointerCenterX - 3.2,
                y: rect.maxY - 1.8
            ),
            control2: CGPoint(
                x: pointerCenterX - 5.5,
                y: bodyHeight + 0.2
            )
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: bodyHeight))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + radius),
            control1: CGPoint(
                x: rect.minX + radius - curve * radius,
                y: bodyHeight
            ),
            control2: CGPoint(
                x: rect.minX,
                y: rect.minY + radius + curve * radius
            )
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control1: CGPoint(
                x: rect.minX,
                y: rect.minY + radius - curve * radius
            ),
            control2: CGPoint(
                x: rect.minX + radius - curve * radius,
                y: rect.minY
            )
        )
        path.closeSubpath()
        return path
    }
}

private struct PopupClickProtectedKey: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []

    static func reduce(
        value: inout [Anchor<CGRect>],
        nextValue: () -> [Anchor<CGRect>]
    ) {
        value.append(contentsOf: nextValue())
    }
}

private extension View {
    func popupClickProtected() -> some View {
        anchorPreference(
            key: PopupClickProtectedKey.self,
            value: .bounds
        ) { [$0] }
    }
}

struct PopupHorizontalPlacement: Equatable {
    let bubbleCenterOffset: CGFloat
    let pointerOffset: CGFloat

    nonisolated static func resolve(
        anchorOffset: CGFloat,
        containerWidth: CGFloat,
        bubbleWidth: CGFloat,
        horizontalInset: CGFloat,
        pointerEdgeInset: CGFloat
    ) -> Self {
        let maximumCenterOffset = max(
            (containerWidth - bubbleWidth) / 2 - horizontalInset,
            0
        )
        let bubbleCenterOffset = min(
            max(anchorOffset, -maximumCenterOffset),
            maximumCenterOffset
        )
        let maximumPointerOffset = max(
            bubbleWidth / 2 - pointerEdgeInset,
            0
        )
        let pointerOffset = min(
            max(
                anchorOffset - bubbleCenterOffset,
                -maximumPointerOffset
            ),
            maximumPointerOffset
        )
        return Self(
            bubbleCenterOffset: bubbleCenterOffset,
            pointerOffset: pointerOffset
        )
    }
}

enum PopupDismissalPolicy {
    nonisolated static func shouldDismiss(
        clickPoint: CGPoint,
        protectedRects: [CGRect],
        hitSlop: CGFloat = 4
    ) -> Bool {
        !protectedRects.contains { rect in
            rect.insetBy(dx: -hitSlop, dy: -hitSlop)
                .contains(clickPoint)
        }
    }
}

private struct PopupOutsideClickMonitor: NSViewRepresentable {
    let isPresented: Bool
    let protectedRects: [CGRect]
    let dismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ view: MonitoringView, context: Context) {
        context.coordinator.view = view
        context.coordinator.isPresented = isPresented
        context.coordinator.protectedRects = protectedRects
        context.coordinator.dismiss = dismiss
    }

    static func dismantleNSView(
        _ view: MonitoringView,
        coordinator: Coordinator
    ) {
        coordinator.stopMonitoring()
    }

    final class MonitoringView: NSView {
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var view: MonitoringView?
        var isPresented = false
        var protectedRects: [CGRect] = []
        var dismiss: () -> Void
        private var eventMonitor: Any?
        private var globalEventMonitor: Any?

        init(dismiss: @escaping () -> Void) {
            self.dismiss = dismiss
            super.init()
        }

        func startMonitoring() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                self?.handle(event)
                return event
            }
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                self?.dismissIfPresented()
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowResignation(_:)),
                name: NSWindow.didResignKeyNotification,
                object: nil,
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleApplicationResignation(_:)),
                name: NSApplication.didResignActiveNotification,
                object: nil,
            )
        }

        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            eventMonitor = nil
            if let globalEventMonitor {
                NSEvent.removeMonitor(globalEventMonitor)
            }
            globalEventMonitor = nil
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResignKeyNotification,
                object: nil
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSApplication.didResignActiveNotification,
                object: nil
            )
        }

        private func handle(_ event: NSEvent) {
            guard
                isPresented,
                let view,
                let window = view.window,
                event.window === window
            else { return }
            let point = view.convert(event.locationInWindow, from: nil)
            guard PopupDismissalPolicy.shouldDismiss(
                clickPoint: point,
                protectedRects: protectedRects
            ) else { return }

            dismissIfPresented()
        }

        @objc private func handleWindowResignation(
            _ notification: Notification
        ) {
            guard
                isPresented,
                let view,
                notification.object as? NSWindow === view.window
            else { return }
            dismissIfPresented()
        }

        @objc private func handleApplicationResignation(
            _ notification: Notification
        ) {
            dismissIfPresented()
        }

        private func dismissIfPresented() {
            guard isPresented else { return }
            DispatchQueue.main.async { [weak self] in
                guard self?.isPresented == true else { return }
                self?.dismiss()
            }
        }
    }
}

private struct PrimarySecondaryClickTarget: NSViewRepresentable {
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHelp: String
    let accessibilityIdentifier: String
    let isSelected: Bool
    let action: () -> Void
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView(action: action, onHover: onHover)
        configureAccessibility(for: view)
        return view
    }

    func updateNSView(_ view: ClickView, context: Context) {
        view.action = action
        view.onHover = onHover
        configureAccessibility(for: view)
    }

    private func configureAccessibility(for view: ClickView) {
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(accessibilityLabel)
        view.setAccessibilityValue(accessibilityValue)
        view.setAccessibilityHelp(accessibilityHelp)
        view.setAccessibilityIdentifier(accessibilityIdentifier)
        view.setAccessibilitySelected(isSelected)
    }

    final class ClickView: NSView {
        var action: () -> Void
        var onHover: (Bool) -> Void
        private var trackingArea: NSTrackingArea?
        private var tracksPrimaryClick = false
        private var tracksSecondaryClick = false

        init(
            action: @escaping () -> Void,
            onHover: @escaping (Bool) -> Void
        ) {
            self.action = action
            self.onHover = onHover
            super.init(frame: .zero)
            focusRingType = .none
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override var acceptsFirstResponder: Bool { true }

        override func becomeFirstResponder() -> Bool {
            // SwiftUI can nominate the first representable view when the
            // settings window opens. Show a focus ring only for an explicit
            // keyboard traversal, never for that automatic initial focus or
            // a pointer click.
            focusRingType = NSApp.currentEvent?.type == .keyDown
                && NSApp.currentEvent?.keyCode == 48
                ? .default
                : .none
            return super.becomeFirstResponder()
        }

        override func resignFirstResponder() -> Bool {
            focusRingType = .none
            return super.resignFirstResponder()
        }

        override var focusRingMaskBounds: NSRect {
            bounds.insetBy(dx: 3, dy: 7)
        }

        override func drawFocusRingMask() {
            NSBezierPath(
                roundedRect: focusRingMaskBounds,
                xRadius: 8,
                yRadius: 8
            ).fill()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let trackingArea = NSTrackingArea(
                rect: .zero,
                options: [
                    .activeAlways,
                    .inVisibleRect,
                    .mouseEnteredAndExited
                ],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            self.trackingArea = trackingArea
        }

        override func mouseEntered(with event: NSEvent) {
            onHover(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover(false)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(nil)
            tracksPrimaryClick = true
        }

        override func mouseUp(with event: NSEvent) {
            guard tracksPrimaryClick else { return }
            tracksPrimaryClick = false
            guard contains(event) else { return }
            action()
        }

        override func rightMouseDown(with event: NSEvent) {
            window?.makeFirstResponder(nil)
            tracksSecondaryClick = true
        }

        override func rightMouseUp(with event: NSEvent) {
            guard tracksSecondaryClick else { return }
            tracksSecondaryClick = false
            guard contains(event) else { return }
            action()
        }

        private func contains(_ event: NSEvent) -> Bool {
            bounds.contains(convert(event.locationInWindow, from: nil))
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36, 49: // Return and Space
                action()
            default:
                super.keyDown(with: event)
            }
        }

        override func accessibilityPerformPress() -> Bool {
            action()
            return true
        }
    }
}

enum DemoSwipeRegionPolicy {
    nonisolated static func contains(
        _ point: CGPoint,
        in bounds: CGRect,
        bottomExtension: CGFloat
    ) -> Bool {
        CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: bounds.height + max(bottomExtension, 0)
        ).contains(point)
    }
}

private struct TrackpadSwipeMonitor: NSViewRepresentable {
    let bottomExtension: CGFloat
    let onSwipe: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            bottomExtension: bottomExtension,
            onSwipe: onSwipe
        )
    }

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ view: MonitoringView, context: Context) {
        context.coordinator.view = view
        context.coordinator.bottomExtension = bottomExtension
        context.coordinator.onSwipe = onSwipe
    }

    static func dismantleNSView(
        _ view: MonitoringView,
        coordinator: Coordinator
    ) {
        coordinator.stopMonitoring()
    }

    final class MonitoringView: NSView {
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    @MainActor
    final class Coordinator {
        weak var view: MonitoringView?
        var bottomExtension: CGFloat = 0
        var onSwipe: (Int) -> Void
        private var monitor: Any?
        private var accumulatedDelta: CGFloat = 0
        private var didTrigger = false

        init(
            bottomExtension: CGFloat,
            onSwipe: @escaping (Int) -> Void
        ) {
            self.bottomExtension = bottomExtension
            self.onSwipe = onSwipe
        }

        func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            guard
                event.hasPreciseScrollingDeltas,
                let view,
                event.window === view.window,
                DemoSwipeRegionPolicy.contains(
                    view.convert(event.locationInWindow, from: nil),
                    in: view.bounds,
                    bottomExtension: bottomExtension
                ),
                abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            else { return }

            if event.phase == .began {
                accumulatedDelta = 0
                didTrigger = false
            }
            accumulatedDelta += event.scrollingDeltaX
            if !didTrigger, abs(accumulatedDelta) >= 18 {
                didTrigger = true
                onSwipe(accumulatedDelta < 0 ? 1 : -1)
            }
            if event.phase == .ended || event.phase == .cancelled {
                accumulatedDelta = 0
                didTrigger = false
            }
        }
    }
}

private struct DiscreteSliderColumn: View {
    let title: String
    @Binding var value: Double
    let steps: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            DiscreteSlider(
                value: $value,
                steps: steps,
                accessibilityLabel: title
            )
            .frame(height: 25)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiscreteSlider: NSViewRepresentable {
    @Binding var value: Double
    let steps: [Double]
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSlider {
        precondition(steps.count >= 2)
        let slider = NSSlider(
            value: value,
            minValue: steps[0],
            maxValue: steps[steps.count - 1],
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.isContinuous = true
        slider.numberOfTickMarks = steps.count
        slider.tickMarkPosition = .below
        slider.allowsTickMarkValuesOnly = true
        slider.setAccessibilityLabel(accessibilityLabel)
        updateAccessibilityValue(of: slider)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.doubleValue = value
        slider.setAccessibilityLabel(accessibilityLabel)
        updateAccessibilityValue(of: slider)
    }

    private func updateAccessibilityValue(of slider: NSSlider) {
        let closestIndex = steps.indices.min { lhs, rhs in
            abs(steps[lhs] - value) < abs(steps[rhs] - value)
        } ?? steps.startIndex
        slider.setAccessibilityValue(
            OrbitL10n.format(
                "settings.slider.accessibility.value",
                fallback: "Деление %ld из %ld",
                closestIndex + 1,
                steps.count
            )
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: DiscreteSlider

        init(parent: DiscreteSlider) { self.parent = parent }

        @objc func valueChanged(_ sender: NSSlider) {
            parent.value = sender.doubleValue
        }
    }
}
