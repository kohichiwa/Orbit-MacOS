import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let contentSize = NSSize(width: 540, height: 640)

    init(settings: AppSettings, viewModel: SpaceViewModel) {
        let rootView = SettingsRootView(
            settings: settings,
            viewModel: viewModel
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
        window.title = "Настройки"
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
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
}

private final class SettingsWindowBackgroundView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
        isEmphasized = true
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
    @ObservedObject var viewModel: SpaceViewModel

    private var colorSlotCount: Int {
        max(
            viewModel.indicatorKinds.map(\.colorIndex).max().map { $0 + 1 }
                ?? 1,
            1
        )
    }

    var body: some View {
        ZStack {
            SettingsSurfaceBackground()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                InteractiveDemoZone(
                    indicators: viewModel.indicatorKinds,
                    currentActiveIndex: viewModel.activeIndex,
                    colors: settings.indicatorColors(for: colorSlotCount),
                    sizeScale: settings.indicatorSizeScale,
                    spacingScale: settings.indicatorSpacingScale,
                    showsThinOutline: settings.showsIndicatorOutline,
                    shapeStyle: settings.indicatorShapeStyle,
                    animationsEnabled: settings.animateIndicator,
                    animationStyle: settings.indicatorAnimationStyle,
                    setColor: settings.setIndicatorColor
                )
                .frame(height: SettingsSurfaceMetrics.demoHeight)
                .ignoresSafeArea(.container, edges: .top)

                SettingsControls(settings: settings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 540, height: 640)
        .background(Color.clear)
    }
}

private enum SettingsSurfaceMetrics {
    static let demoHeight: CGFloat = 218
    static let transparentHeight: CGFloat = 180
    static let gradientHeight: CGFloat = 110
    static let demoSwipeBottomExtension = max(
        transparentHeight + gradientHeight - demoHeight,
        0
    )
}

private struct SettingsSurfaceBackground: View {
    private let opaqueBackground = Color(nsColor: .windowBackgroundColor)

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: SettingsSurfaceMetrics.transparentHeight)

            LinearGradient(
                colors: [
                    .clear,
                    opaqueBackground.opacity(0.04),
                    opaqueBackground.opacity(0.12),
                    opaqueBackground.opacity(0.26),
                    opaqueBackground.opacity(0.46),
                    opaqueBackground.opacity(0.70),
                    opaqueBackground.opacity(0.88),
                    opaqueBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: SettingsSurfaceMetrics.gradientHeight)

            opaqueBackground
        }
        .ignoresSafeArea()
    }
}

@MainActor
private struct SettingsControls: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SettingsSectionTitle(
                        title: "Оформление",
                        symbol: "circle.lefthalf.filled"
                    )
                    Spacer()
                    Button {
                        settings.resetIndicatorColors()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("Сбросить цвета")
                }

                SettingsGroup {
                    DiscreteSliderRow(
                        title: "Размер",
                        value: Binding(
                            get: { settings.indicatorSizeScale },
                            set: { settings.setIndicatorSizeScale($0) }
                        ),
                        steps: AppSettings.indicatorSizeSteps
                    )

                    DiscreteSliderRow(
                        title: "Расстояние",
                        value: Binding(
                            get: { settings.indicatorSpacingScale },
                            set: { settings.setIndicatorSpacingScale($0) }
                        ),
                        steps: AppSettings.indicatorSpacingSteps
                    )

                    ShapeStyleRow(
                        selection: $settings.indicatorShapeStyle
                    )

                    SettingsToggleRow(
                        title: "Обводка",
                        isOn: $settings.showsIndicatorOutline
                    )
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SettingsSectionTitle(
                    title: "Поведение",
                    symbol: "switch.2"
                )

                SettingsGroup {
                    SettingsToggleRow(
                        title: "Анимация",
                        isOn: $settings.animateIndicator
                    )

                    AnimationStyleRow(
                        selection: $settings.indicatorAnimationStyle,
                        isEnabled: settings.animateIndicator
                    )

                    SettingsToggleRow(
                        title: "Запускать при входе",
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
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

private enum SettingsGridMetrics {
    static let labelWidth: CGFloat = 128
    static let columnSpacing: CGFloat = 16
    static let horizontalInset: CGFloat = 16
}

private struct SettingsGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, SettingsGridMetrics.horizontalInset)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.5)
        }
    }
}

private struct SettingsRowLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.callout)
            .foregroundStyle(.primary)
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
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Text(title)
                .font(.headline)
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: SettingsGridMetrics.columnSpacing) {
            SettingsRowLabel(title: title)
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(height: 42)
    }
}

private struct AnimationStyleRow: View {
    @Binding var selection: IndicatorAnimationStyle
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: SettingsGridMetrics.columnSpacing) {
            SettingsRowLabel(title: "Стиль")
            AnimationStyleSelector(
                selection: $selection,
                isEnabled: isEnabled
            )
            .frame(maxWidth: .infinity)
        }
        .frame(height: 48)
    }
}

private struct ShapeStyleRow: View {
    @Binding var selection: IndicatorShapeStyle

    var body: some View {
        HStack(spacing: SettingsGridMetrics.columnSpacing) {
            SettingsRowLabel(title: "Форма")
            ShapeStyleSelector(selection: $selection)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 42)
    }
}

private struct ShapeStyleSelector: View {
    @Binding var selection: IndicatorShapeStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredStyle: IndicatorShapeStyle?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(IndicatorShapeStyle.allCases) { style in
                Button {
                    selection = style
                } label: {
                    HStack(spacing: 6) {
                        shapePreview(for: style)
                            .accessibilityHidden(true)
                        Text(style.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(backgroundColor(for: style))
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 8,
                                    style: .continuous
                                )
                                .strokeBorder(
                                    borderColor(for: style),
                                    lineWidth: 1
                                )
                            }
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredStyle = hovering ? style : nil
                }
                .accessibilityLabel("Форма индикаторов: \(style.title)")
                .accessibilityAddTraits(
                    selection == style ? .isSelected : []
                )
            }
        }
        .animation(
            OrbitMotion.selectionHover(reduceMotion: reduceMotion),
            value: hoveredStyle
        )
        .animation(
            OrbitMotion.selectionChange(reduceMotion: reduceMotion),
            value: selection
        )
    }

    @ViewBuilder
    private func shapePreview(for style: IndicatorShapeStyle) -> some View {
        switch style {
        case .standard:
            HStack(spacing: 3) {
                Circle()
                    .fill(previewColor(for: style))
                    .frame(width: 5, height: 5)
                Capsule(style: .continuous)
                    .fill(previewColor(for: style))
                    .frame(width: 13, height: 7)
            }
            .frame(width: 23, height: 10)
        case .circles:
            HStack(spacing: 3) {
                Circle()
                    .fill(previewColor(for: style))
                    .frame(width: 5, height: 5)
                Circle()
                    .fill(previewColor(for: style))
                    .frame(width: 8, height: 8)
            }
            .frame(width: 23, height: 10)
        case .roundedRectangles:
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1.4, style: .continuous)
                    .fill(previewColor(for: style))
                    .frame(width: 6, height: 6)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(previewColor(for: style))
                    .frame(width: 13, height: 7)
            }
            .frame(width: 23, height: 10)
        }
    }

    private func previewColor(for style: IndicatorShapeStyle) -> Color {
        selection == style ? .accentColor : .secondary
    }

    private func backgroundColor(for style: IndicatorShapeStyle) -> Color {
        if selection == style {
            return Color.accentColor.opacity(0.13)
        }
        return Color.primary.opacity(hoveredStyle == style ? 0.065 : 0.025)
    }

    private func borderColor(for style: IndicatorShapeStyle) -> Color {
        selection == style
            ? Color.accentColor.opacity(0.28)
            : Color.primary.opacity(hoveredStyle == style ? 0.12 : 0.07)
    }
}

private struct AnimationStyleSelector: View {
    @Binding var selection: IndicatorAnimationStyle
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredStyle: IndicatorAnimationStyle?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(IndicatorAnimationStyle.allCases) { style in
                Button {
                    selection = style
                } label: {
                    HStack(spacing: 6) {
                        animationPreview(for: style)
                            .accessibilityHidden(true)
                        Text(style.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(backgroundColor(for: style))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        borderColor(for: style),
                                        lineWidth: 1
                                    )
                            }
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredStyle = hovering ? style : nil
                }
                .accessibilityLabel("Стиль анимации: \(style.title)")
                .accessibilityAddTraits(selection == style ? .isSelected : [])
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(
            OrbitMotion.selectionHover(reduceMotion: reduceMotion),
            value: hoveredStyle
        )
        .animation(
            OrbitMotion.selectionChange(reduceMotion: reduceMotion),
            value: selection
        )
    }

    @ViewBuilder
    private func animationPreview(
        for style: IndicatorAnimationStyle
    ) -> some View {
        switch style {
        case .seamless:
            HStack(spacing: 2) {
                Circle()
                    .fill(previewColor(for: style))
                    .frame(width: 4, height: 4)
                Capsule(style: .continuous)
                    .fill(previewColor(for: style).opacity(0.68))
                    .frame(width: 6, height: 5)
                Capsule(style: .continuous)
                    .fill(previewColor(for: style))
                    .frame(width: 9, height: 6)
            }
            .frame(width: 23, height: 10)
        case .continuous:
            ZStack {
                Capsule(style: .continuous)
                    .fill(previewColor(for: style).opacity(0.32))
                    .frame(width: 19, height: 5)
                Circle()
                    .fill(previewColor(for: style))
                    .frame(width: 7, height: 7)
                    .offset(x: -6)
                Capsule(style: .continuous)
                    .fill(previewColor(for: style))
                    .frame(width: 12, height: 7)
                    .offset(x: 5)
            }
            .frame(width: 23, height: 10)
        case .classic:
            HStack(spacing: 5) {
                Circle()
                    .fill(previewColor(for: style))
                    .frame(width: 6, height: 6)
                Capsule(style: .continuous)
                    .fill(previewColor(for: style))
                    .frame(width: 11, height: 6)
            }
            .frame(width: 23, height: 10)
        }
    }

    private func previewColor(for style: IndicatorAnimationStyle) -> Color {
        selection == style ? .accentColor : .secondary
    }

    private func backgroundColor(
        for style: IndicatorAnimationStyle
    ) -> Color {
        if selection == style {
            return Color.accentColor.opacity(0.13)
        }
        return Color.primary.opacity(hoveredStyle == style ? 0.065 : 0.025)
    }

    private func borderColor(for style: IndicatorAnimationStyle) -> Color {
        selection == style
            ? Color.accentColor.opacity(0.28)
            : Color.primary.opacity(hoveredStyle == style ? 0.12 : 0.07)
    }
}

private struct DemoVisualConfiguration: Equatable {
    let sizeScale: Double
    let spacingScale: Double
    let showsThinOutline: Bool
    let shapeStyle: IndicatorShapeStyle
    let animationsEnabled: Bool
    let animationStyle: IndicatorAnimationStyle
}

private struct InteractiveDemoZone: View {
    private static let maximumArtworkWidth: CGFloat = 484

    let indicators: [SpaceIndicatorKind]
    let currentActiveIndex: Int?
    let colors: [NSColor]
    let sizeScale: Double
    let spacingScale: Double
    let showsThinOutline: Bool
    let shapeStyle: IndicatorShapeStyle
    let animationsEnabled: Bool
    let animationStyle: IndicatorAnimationStyle
    let setColor: (NSColor, Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeIndex = 0
    @State private var hoveredIndex: Int?
    @State private var paletteIndex: Int?
    @State private var paletteRequestID = UUID()
    @State private var glowIsVisible = false
    @State private var isInfoPresented = false
    @State private var isInfoHovered = false

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
                        hoveredIndex: hoveredIndex,
                        sizeScale: demoScale,
                        spacingScale: CGFloat(configuration.spacingScale),
                        showsThinOutline: configuration.showsThinOutline,
                        shapeStyle: configuration.shapeStyle,
                        animationsEnabled: configuration.animationsEnabled,
                        animationStyle: configuration.animationStyle,
                        reduceMotion: reduceMotion
                    )

                    HStack(spacing: 0) {
                        ForEach(indicators.indices, id: \.self) { index in
                            Color.clear
                                .frame(width: demoItemWidth, height: 45)
                                .contentShape(Rectangle())
                                .overlay {
                                    PrimarySecondaryClickTarget(
                                        action: {
                                            select(index)
                                        },
                                        onHover: { hovering in
                                            if hovering {
                                                hoveredIndex = index
                                            } else if hoveredIndex == index {
                                                hoveredIndex = nil
                                            }
                                        }
                                    )
                                }
                                .accessibilityLabel(
                                    indicatorAccessibilityLabel(for: index)
                                )
                        }
                    }
                }
                .frame(width: demoArtworkWidth, height: 45)
                .offset(y: 26)
                .popupClickProtected()
            }

            if let paletteIndex, indicators.indices.contains(paletteIndex) {
                IndicatorColorPalette(
                    selectedColorID: PaletteColor.matchingID(
                        for: color(for: indicators[paletteIndex])
                    ),
                    selectColor: { paletteColor in
                        setColor(
                            paletteColor.color,
                            indicators[paletteIndex].colorIndex
                        )
                    }
                )
                .id(paletteIndex)
                .offset(
                    x: paletteHorizontalOffset(for: paletteIndex),
                    y: -20
                )
                .popupClickProtected()
                .transition(paletteTransition)
                .zIndex(20)
            }

            HStack(alignment: .top, spacing: 4) {
                if isInfoPresented {
                    DemoInfoBubble()
                        .popupClickProtected()
                        .transition(paletteTransition)
                }

                Button {
                    toggleInfo()
                } label: {
                    Image(systemName: "info")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 23, height: 23)
                        .background(
                            isInfoHovered
                                ? Color.primary.opacity(0.075)
                                : Color.primary.opacity(0.035),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    Color.primary.opacity(
                                        isInfoPresented ? 0.22 : 0.12
                                    ),
                                    lineWidth: 0.75
                                )
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .onHover { isInfoHovered = $0 }
                .popupClickProtected()
                .accessibilityLabel("Справка по демонстрации")
                .accessibilityValue(
                    isInfoPresented ? "Открыта" : "Закрыта"
                )
            }
            .padding(.top, 14)
            .padding(.trailing, 14)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topTrailing
            )
            .animation(paletteSpring, value: isInfoPresented)
            .animation(
                OrbitMotion.selectionHover(reduceMotion: reduceMotion),
                value: isInfoHovered
            )
            .zIndex(30)

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
            paletteRequestID = UUID()
            withAnimation(paletteSpring) {
                paletteIndex = nil
                isInfoPresented = false
            }
        }
        .onChange(of: currentActiveIndex) { synchronizeActiveIndex() }
        .onChange(of: indicators.count) {
            guard !indicators.isEmpty else {
                activeIndex = 0
                paletteIndex = nil
                return
            }
            activeIndex = min(activeIndex, indicators.count - 1)
            if let paletteIndex, !indicators.indices.contains(paletteIndex) {
                self.paletteIndex = nil
            }
        }
        .overlayPreferenceValue(PopupClickProtectedKey.self) { anchors in
            GeometryReader { proxy in
                PopupOutsideClickMonitor(
                    isPresented: paletteIndex != nil || isInfoPresented,
                    protectedRects: anchors.map { proxy[$0] },
                    dismiss: dismissPopups
                )
                .allowsHitTesting(false)
            }
        }
    }

    private var demoScale: CGFloat {
        let requestedScale = CGFloat(configuration.sizeScale) * 2.15
        let requestedWidth = demoArtworkWidth(for: requestedScale)
        guard requestedWidth > Self.maximumArtworkWidth else {
            return requestedScale
        }
        return requestedScale * Self.maximumArtworkWidth / requestedWidth
    }

    private var demoItemWidth: CGFloat {
        StatusItemArtwork.itemWidth(
            sizeScale: demoScale,
            spacingScale: CGFloat(configuration.spacingScale)
        )
    }

    private var demoArtworkWidth: CGFloat {
        demoArtworkWidth(for: demoScale)
    }

    private func demoArtworkWidth(for sizeScale: CGFloat) -> CGFloat {
        CGFloat(indicators.count) * StatusItemArtwork.itemWidth(
            sizeScale: sizeScale,
            spacingScale: CGFloat(configuration.spacingScale)
        )
            + SyncedIndicatorArtworkView.horizontalOverflowPadding(
                for: sizeScale,
                spacingScale: CGFloat(configuration.spacingScale)
            ) * 2
    }

    private var paletteSpring: Animation? {
        OrbitMotion.palette(
            enabled: configuration.animationsEnabled,
            reduceMotion: reduceMotion
        )
    }

    private var paletteTransition: AnyTransition {
        reduceMotion ? .opacity : .liquidPalette
    }

    private var glowAnimation: Animation? {
        OrbitMotion.indicatorChange(
            style: configuration.animationStyle,
            enabled: configuration.animationsEnabled,
            reduceMotion: reduceMotion
        )
    }

    private var requestedConfiguration: DemoVisualConfiguration {
        DemoVisualConfiguration(
            sizeScale: sizeScale,
            spacingScale: spacingScale,
            showsThinOutline: showsThinOutline,
            shapeStyle: shapeStyle,
            animationsEnabled: animationsEnabled,
            animationStyle: animationStyle
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
        return paletteHorizontalOffset(for: activeIndex)
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
        activeIndex = index
        let requestID = UUID()
        paletteRequestID = requestID

        if isInfoPresented {
            withAnimation(paletteSpring) {
                isInfoPresented = false
            }
        }

        guard paletteIndex != index else {
            withAnimation(paletteSpring) {
                paletteIndex = nil
            }
            return
        }

        guard paletteIndex != nil else {
            withAnimation(paletteSpring) {
                paletteIndex = index
            }
            return
        }

        // Finish the vertical exit above the old indicator before presenting
        // the palette above another one. This prevents a diagonal flight
        // between two unrelated indicator centers.
        withAnimation(paletteSpring) {
            paletteIndex = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            guard paletteRequestID == requestID else { return }
            withAnimation(paletteSpring) {
                paletteIndex = index
            }
        }
    }

    private func paletteHorizontalOffset(for index: Int) -> CGFloat {
        let centeredIndex = CGFloat(index)
            - CGFloat(indicators.count - 1) / 2
        return centeredIndex * demoItemWidth
    }

    private func moveActive(by offset: Int) {
        guard !indicators.isEmpty else { return }
        paletteRequestID = UUID()
        withAnimation(paletteSpring) {
            paletteIndex = nil
        }
        let destination = activeIndex + offset
        guard indicators.indices.contains(destination) else { return }
        activeIndex = destination
    }

    private func indicatorAccessibilityLabel(for index: Int) -> String {
        switch indicators[index] {
        case .desktop:
            "Рабочий стол \(indicators[index].colorIndex + 1) — нажмите, чтобы изменить цвет"
        case .fullscreen:
            "Полноэкранное приложение — используется цвет связанного рабочего стола"
        }
    }

    private func toggleInfo() {
        paletteRequestID = UUID()
        withAnimation(paletteSpring) {
            paletteIndex = nil
            isInfoPresented.toggle()
        }
    }

    private func dismissPopups() {
        guard paletteIndex != nil || isInfoPresented else { return }
        paletteRequestID = UUID()
        withAnimation(paletteSpring) {
            paletteIndex = nil
            isInfoPresented = false
        }
    }

    private func synchronizeActiveIndex() {
        guard
            let currentActiveIndex,
            indicators.indices.contains(currentActiveIndex)
        else { return }
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
        PaletteColor(id: "red", title: "Красный", color: .systemRed),
        PaletteColor(id: "orange", title: "Оранжевый", color: .systemOrange),
        PaletteColor(id: "yellow", title: "Жёлтый", color: .systemYellow),
        PaletteColor(id: "green", title: "Зелёный", color: .systemGreen),
        PaletteColor(id: "blue", title: "Синий", color: .systemBlue),
        PaletteColor(id: "purple", title: "Фиолетовый", color: .systemPurple)
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

private struct IndicatorColorPalette: View {
    let selectedColorID: String?
    let selectColor: (PaletteColor) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PaletteColor.choices) { choice in
                Button {
                    selectColor(choice)
                } label: {
                    ZStack {
                        Circle().fill(Color(nsColor: choice.color))
                        Circle().stroke(
                            Color.white.opacity(0.32),
                            lineWidth: 0.7
                        )
                        Circle()
                            .stroke(
                                choice.id == selectedColorID
                                    ? Color.primary.opacity(0.78)
                                    : .clear,
                                lineWidth: 2
                            )
                            .padding(-3)
                    }
                    .frame(width: 17, height: 17)
                    .contentShape(Circle())
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.title)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 39)
        .padding(.bottom, 9)
        .stableBubbleSurface(PaletteBubbleShape())
        .fixedSize()
    }

}

private struct DemoInfoBubble: View {
    var body: some View {
        Text("Клик — изменить цвет\nСвайп двумя пальцами — листать")
            .font(.system(size: 11.5))
            .foregroundStyle(.primary)
            .lineSpacing(1)
            .padding(.leading, 12)
            .padding(.trailing, 20)
            .padding(.vertical, 12)
            .frame(width: 224, alignment: .leading)
            .stableBubbleSurface(InfoBubbleShape())
            .accessibilityElement(children: .combine)
    }
}

private struct StableBubbleSurface<Surface: Shape>: ViewModifier {
    let surface: Surface

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: surface)
            .overlay {
                surface
                    .stroke(
                        Color.primary.opacity(0.13),
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

private struct InfoBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let pointerWidth: CGFloat = 8
        let pointerHalfWidth: CGFloat = 6
        let radius: CGFloat = 14
        let pointerCenterY = rect.minY + 20
        let bodyRight = rect.maxX - pointerWidth
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: bodyRight - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: bodyRight, y: rect.minY + radius),
            control: CGPoint(x: bodyRight, y: rect.minY)
        )
        path.addLine(
            to: CGPoint(x: bodyRight, y: pointerCenterY - pointerHalfWidth)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - 1.1, y: pointerCenterY - 1.4),
            control1: CGPoint(x: bodyRight + 0.2, y: pointerCenterY - 4.5),
            control2: CGPoint(x: rect.maxX - 1.7, y: pointerCenterY - 2.7)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 1.1, y: pointerCenterY + 1.4),
            control: CGPoint(x: rect.maxX + 0.3, y: pointerCenterY)
        )
        path.addCurve(
            to: CGPoint(x: bodyRight, y: pointerCenterY + pointerHalfWidth),
            control1: CGPoint(x: rect.maxX - 1.7, y: pointerCenterY + 2.7),
            control2: CGPoint(x: bodyRight + 0.2, y: pointerCenterY + 4.5)
        )
        path.addLine(to: CGPoint(x: bodyRight, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: bodyRight - radius, y: rect.maxY),
            control: CGPoint(x: bodyRight, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct PaletteBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let pointerHeight: CGFloat = 9
        let bodyHeight = rect.height - pointerHeight
        let radius = bodyHeight / 2
        let curve: CGFloat = 0.552_284_8
        let pointerHalfWidth: CGFloat = 9
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
            to: CGPoint(x: rect.midX + pointerHalfWidth, y: bodyHeight)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX + 1.6, y: rect.maxY - 1.2),
            control1: CGPoint(
                x: rect.midX + 5.5,
                y: bodyHeight + 0.2
            ),
            control2: CGPoint(x: rect.midX + 3.2, y: rect.maxY - 1.8)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX - 1.6, y: rect.maxY - 1.2),
            control: CGPoint(x: rect.midX, y: rect.maxY + 0.5)
        )
        path.addCurve(
            to: CGPoint(
                x: rect.midX - pointerHalfWidth,
                y: bodyHeight
            ),
            control1: CGPoint(x: rect.midX - 3.2, y: rect.maxY - 1.8),
            control2: CGPoint(
                x: rect.midX - 5.5,
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
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowResignation(_:)),
                name: NSWindow.didResignKeyNotification,
                object: nil,
            )
        }

        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            eventMonitor = nil
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResignKeyNotification,
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

            DispatchQueue.main.async { [weak self] in
                guard self?.isPresented == true else { return }
                self?.dismiss()
            }
        }

        @objc private func handleWindowResignation(
            _ notification: Notification
        ) {
            guard
                isPresented,
                let view,
                notification.object as? NSWindow === view.window
            else { return }
            dismiss()
        }
    }
}

private struct PrimarySecondaryClickTarget: NSViewRepresentable {
    let action: () -> Void
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> ClickView {
        ClickView(action: action, onHover: onHover)
    }

    func updateNSView(_ view: ClickView, context: Context) {
        view.action = action
        view.onHover = onHover
    }

    final class ClickView: NSView {
        var action: () -> Void
        var onHover: (Bool) -> Void
        private var trackingArea: NSTrackingArea?

        init(
            action: @escaping () -> Void,
            onHover: @escaping (Bool) -> Void
        ) {
            self.action = action
            self.onHover = onHover
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
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
            action()
        }

        override func rightMouseDown(with event: NSEvent) {
            action()
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

private struct DiscreteSliderRow: View {
    let title: String
    @Binding var value: Double
    let steps: [Double]

    var body: some View {
        HStack(spacing: SettingsGridMetrics.columnSpacing) {
            SettingsRowLabel(title: title)
            DiscreteSlider(
                value: $value,
                steps: steps,
                accessibilityLabel: title
            )
            .frame(height: 25)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 48)
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
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.doubleValue = value
        slider.setAccessibilityLabel(accessibilityLabel)
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
