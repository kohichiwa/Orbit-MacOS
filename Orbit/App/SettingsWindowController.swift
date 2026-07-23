import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let contentSize = NSSize(width: 540, height: 640)
    private let presentationState: SettingsPresentationState

    init(settings: AppSettings, viewModel: SpaceViewModel) {
        let presentationState = SettingsPresentationState()
        self.presentationState = presentationState
        let rootView = SettingsRootView(
            settings: settings,
            viewModel: viewModel,
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
                            viewModel: viewModel
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
        .frame(width: 540, height: 640)
        .background(Color.clear)
    }
}

@MainActor
private struct SettingsLiveDemo: View {
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
            }
        }
        .ignoresSafeArea()
    }
}

@MainActor
private struct SettingsControls: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(
                title: OrbitL10n.text(
                    "settings.section.appearance",
                    fallback: "Оформление"
                ),
                symbol: "circle.lefthalf.filled"
            ) {
                Button {
                    settings.resetIndicatorColors()
                } label: {
                    Label(
                        OrbitL10n.text(
                            "settings.colors.reset",
                            fallback: "Сбросить цвета"
                        ),
                        systemImage: "arrow.counterclockwise"
                    )
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(settings.indicatorColors.isEmpty)
                .help(
                    OrbitL10n.text(
                        "settings.colors.reset.help",
                        fallback: "Вернуть системный цвет всем индикаторам"
                    )
                )
            } content: {
                SettingsGroup {
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
                    .padding(.vertical, 4)

                    ShapeStyleRow(
                        selection: $settings.indicatorShapeStyle
                    )

                    SettingsToggleRow(
                        title: OrbitL10n.text(
                            "settings.outline",
                            fallback: "Обводка"
                        ),
                        isOn: $settings.showsIndicatorOutline
                    )
                }
            }

            SettingsSection(
                title: OrbitL10n.text(
                    "settings.section.behavior",
                    fallback: "Поведение"
                ),
                symbol: "switch.2"
            ) {
                SettingsGroup {
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

private enum SettingsGridMetrics {
    static let windowHorizontalInset: CGFloat = 24
    static let labelWidth: CGFloat = 128
    static let columnSpacing: CGFloat = 14
    static let horizontalInset: CGFloat = 14
    static let groupCornerRadius: CGFloat = 14
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
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

private struct SettingsGroup<Content: View>: View {
    let content: Content
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, SettingsGridMetrics.horizontalInset)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(
                cornerRadius: SettingsGridMetrics.groupCornerRadius,
                style: .continuous
            )
            .fill(
                Color.primary.opacity(
                    colorSchemeContrast == .increased ? 0.08 : 0.04
                )
            )
            .overlay {
                if colorSchemeContrast == .increased {
                    RoundedRectangle(
                        cornerRadius: SettingsGridMetrics.groupCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(Color.primary.opacity(0.20), lineWidth: 1)
                }
            }
        }
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            Color.primary.opacity(
                                colorSchemeContrast == .increased
                                    ? 0.12
                                    : 0.065
                            )
                        )
                }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
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
        .frame(height: 38)
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
            .frame(maxWidth: .infinity)
        }
        .frame(height: 46)
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
                .frame(maxWidth: .infinity)
        }
        .frame(height: 40)
    }
}

private struct ShapeStyleSelector: View {
    @Binding var selection: IndicatorShapeStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var hoveredStyle: IndicatorShapeStyle?

    var body: some View {
        HStack(spacing: 3) {
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
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(backgroundColor(for: style))
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 7,
                                    style: .continuous
                                )
                                .strokeBorder(
                                    borderColor(for: style),
                                    lineWidth: 0.75
                                )
                            }
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredStyle = hovering ? style : nil
                }
                .accessibilityLabel(
                    OrbitL10n.format(
                        "settings.shape.option.accessibility",
                        fallback: "Форма индикаторов: %@",
                        style.title
                    )
                )
                .accessibilityAddTraits(
                    selection == style ? .isSelected : []
                )
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    Color.primary.opacity(
                        colorSchemeContrast == .increased ? 0.09 : 0.045
                    )
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            OrbitL10n.text(
                "settings.shape.accessibility",
                fallback: "Форма индикаторов"
            )
        )
        .accessibilityValue(selection.title)
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
            return Color.accentColor.opacity(0.15)
        }
        let hoverOpacity = colorSchemeContrast == .increased ? 0.12 : 0.06
        return Color.primary.opacity(hoveredStyle == style ? hoverOpacity : 0)
    }

    private func borderColor(for style: IndicatorShapeStyle) -> Color {
        selection == style
            ? Color.accentColor.opacity(
                colorSchemeContrast == .increased ? 0.62 : 0.25
            )
            : .clear
    }
}

private struct AnimationStyleSelector: View {
    @Binding var selection: IndicatorAnimationStyle
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var hoveredStyle: IndicatorAnimationStyle?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(IndicatorAnimationStyle.allCases) { style in
                Button {
                    selection = style
                } label: {
                    HStack(spacing: 5) {
                        animationPreview(for: style)
                            .accessibilityHidden(true)
                        Text(style.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(backgroundColor(for: style))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        borderColor(for: style),
                                        lineWidth: 0.75
                                    )
                            }
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredStyle = hovering ? style : nil
                }
                .accessibilityLabel(
                    OrbitL10n.format(
                        "settings.animation.option.accessibility",
                        fallback: "Стиль анимации: %@",
                        style.title
                    )
                )
                .accessibilityAddTraits(selection == style ? .isSelected : [])
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    Color.primary.opacity(
                        colorSchemeContrast == .increased ? 0.09 : 0.045
                    )
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            OrbitL10n.text(
                "settings.animation.style.accessibility",
                fallback: "Стиль анимации"
            )
        )
        .accessibilityValue(selection.title)
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
            HStack(spacing: 1.5) {
                Circle()
                    .fill(previewColor(for: style).opacity(0.38))
                    .frame(width: 4, height: 4)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(previewColor(for: style).opacity(0.66))
                    .frame(width: 7, height: 5)
                Capsule(style: .continuous)
                    .fill(previewColor(for: style))
                    .frame(width: 11, height: 6)
            }
            .frame(width: 27, height: 10)
        case .continuous:
            ZStack {
                Capsule(style: .continuous)
                    .fill(previewColor(for: style))
                    .frame(width: 19, height: 2.5)
                Circle()
                    .fill(previewColor(for: style))
                    .frame(width: 7, height: 7)
                    .offset(x: -9)
                Capsule(style: .continuous)
                    .fill(previewColor(for: style))
                    .frame(width: 14, height: 8)
                    .offset(x: 7)
            }
            .frame(width: 29, height: 10)
        case .classic:
            HStack(spacing: 2) {
                Circle()
                    .fill(previewColor(for: style))
                    .frame(width: 5, height: 5)
                Image(systemName: "arrow.right")
                    .font(.system(size: 5, weight: .bold))
                    .foregroundStyle(previewColor(for: style).opacity(0.72))
                    .frame(width: 7)
                Capsule(style: .continuous)
                    .fill(previewColor(for: style))
                    .frame(width: 10, height: 6)
            }
            .frame(width: 27, height: 10)
        }
    }

    private func previewColor(for style: IndicatorAnimationStyle) -> Color {
        selection == style ? .accentColor : .secondary
    }

    private func backgroundColor(
        for style: IndicatorAnimationStyle
    ) -> Color {
        if selection == style {
            return Color.accentColor.opacity(0.15)
        }
        let hoverOpacity = colorSchemeContrast == .increased ? 0.12 : 0.06
        return Color.primary.opacity(hoveredStyle == style ? hoverOpacity : 0)
    }

    private func borderColor(for style: IndicatorAnimationStyle) -> Color {
        selection == style
            ? Color.accentColor.opacity(
                colorSchemeContrast == .increased ? 0.62 : 0.25
            )
            : .clear
    }
}

private struct DemoVisualConfiguration: Equatable {
    let sizeScale: Double
    let spacingScale: Double
    let showsThinOutline: Bool
    let shapeStyle: IndicatorShapeStyle
    let animationsEnabled: Bool
    let animationStyle: IndicatorAnimationStyle
    let increasedContrast: Bool
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
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
                        reduceMotion: reduceMotion,
                        increasedContrast: configuration.increasedContrast
                    )

                    HStack(spacing: 0) {
                        ForEach(indicators.indices, id: \.self) { index in
                            Color.clear
                                .frame(width: demoItemWidth, height: 45)
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
                                                hoveredIndex = index
                                            } else if hoveredIndex == index {
                                                hoveredIndex = nil
                                            }
                                        }
                                    )
                                }
                        }
                    }
                }
                .frame(width: demoArtworkWidth, height: 45)
                .offset(y: 26)
                .popupClickProtected()
            }

            GeometryReader { proxy in
                if let paletteIndex, indicators.indices.contains(paletteIndex) {
                    let anchorOffset = paletteHorizontalOffset(for: paletteIndex)
                    let placement = PopupHorizontalPlacement.resolve(
                        anchorOffset: anchorOffset,
                        containerWidth: proxy.size.width,
                        bubbleWidth: IndicatorColorPalette.width,
                        horizontalInset:
                            SettingsGridMetrics.windowHorizontalInset,
                        pointerEdgeInset: IndicatorColorPalette.pointerEdgeInset
                    )

                    IndicatorColorPalette(
                        selectedColorID: PaletteColor.matchingID(
                            for: color(for: indicators[paletteIndex])
                        ),
                        pointerOffset: placement.pointerOffset,
                        selectColor: { paletteColor in
                            setColor(
                                paletteColor.color,
                                indicators[paletteIndex].colorIndex
                            )
                        }
                    )
                    .id(paletteIndex)
                    .position(
                        x: proxy.size.width / 2
                            + placement.bubbleCenterOffset,
                        y: proxy.size.height / 2 - 20
                    )
                    .popupClickProtected()
                    .transition(paletteTransition)
                }
            }
            .zIndex(20)

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
                                    Color.primary.opacity(infoBorderOpacity),
                                    lineWidth: 0.75
                                )
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .onHover { isInfoHovered = $0 }
                .popupClickProtected()
                .accessibilityLabel(
                    OrbitL10n.text(
                        "settings.demo.info.accessibility",
                        fallback: "Справка по демонстрации"
                    )
                )
                .accessibilityValue(
                    isInfoPresented
                        ? OrbitL10n.text(
                            "accessibility.state.open",
                            fallback: "Открыта"
                        )
                        : OrbitL10n.text(
                            "accessibility.state.closed",
                            fallback: "Закрыта"
                        )
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
        StatusItemArtwork.contentWidth(
            for: indicators.count,
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

    private var infoBorderOpacity: Double {
        if colorSchemeContrast == .increased {
            return isInfoPresented ? 0.46 : 0.30
        }
        return isInfoPresented ? 0.22 : 0.12
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

private struct IndicatorColorPalette: View {
    static let width: CGFloat = 170
    static let pointerEdgeInset: CGFloat = 29

    let selectedColorID: String?
    let pointerOffset: CGFloat
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
        .padding(.horizontal, 14)
        .frame(width: Self.width)
        .frame(height: 39)
        .padding(.bottom, 9)
        .stableBubbleSurface(
            PaletteBubbleShape(pointerOffset: pointerOffset)
        )
        .fixedSize()
    }

}

private struct DemoInfoBubble: View {
    var body: some View {
        Text(
            OrbitL10n.text(
                "settings.demo.info",
                fallback: "Клик — изменить цвет\nСвайп двумя пальцами — листать"
            )
        )
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
    let pointerOffset: CGFloat

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
            action()
        }

        override func rightMouseDown(with event: NSEvent) {
            window?.makeFirstResponder(nil)
            action()
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
