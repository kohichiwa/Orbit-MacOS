import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let contentSize = NSSize(width: 680, height: 440)

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
                    animationsEnabled: settings.animateIndicator,
                    animationStyle: settings.indicatorAnimationStyle,
                    setColor: settings.setIndicatorColor
                )
                .frame(height: 194)
                .ignoresSafeArea(.container, edges: .top)

                SettingsControls(settings: settings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 680, height: 440)
        .background(Color.clear)
    }
}

private struct SettingsSurfaceBackground: View {
    private let opaqueBackground = Color(nsColor: .windowBackgroundColor)

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 156)

            LinearGradient(
                colors: [
                    .clear,
                    opaqueBackground.opacity(0.10),
                    opaqueBackground.opacity(0.32),
                    opaqueBackground.opacity(0.64),
                    opaqueBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 66)

            opaqueBackground
        }
        .ignoresSafeArea()
    }
}

@MainActor
private struct SettingsControls: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        SettingsSectionTitle(
                            title: "Внешний вид",
                            symbol: "circle.hexagongrid"
                        )
                        Spacer()
                        Button {
                            settings.resetIndicatorColors()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Сбросить цвета")
                        .accessibilityLabel("Сбросить цвета")
                    }

                    DiscreteSliderRow(
                        title: "Размер индикаторов",
                        value: Binding(
                            get: { settings.indicatorSizeScale },
                            set: { settings.setIndicatorSizeScale($0) }
                        ),
                        steps: AppSettings.indicatorSizeSteps
                    )

                    DiscreteSliderRow(
                        title: "Расстояние между индикаторами",
                        value: Binding(
                            get: { settings.indicatorSpacingScale },
                            set: { settings.setIndicatorSpacingScale($0) }
                        ),
                        steps: AppSettings.indicatorSpacingSteps
                    )
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 158)
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 0) {
                    SettingsSectionTitle(
                        title: "Поведение",
                        symbol: "switch.2"
                    )
                    .padding(.bottom, 5)

                    CompactToggleRow(
                        title: "Анимация индикатора",
                        symbol: "sparkles",
                        isOn: $settings.animateIndicator
                    )

                    Picker(
                        "Стиль анимации",
                        selection: $settings.indicatorAnimationStyle
                    ) {
                        ForEach(IndicatorAnimationStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .disabled(!settings.animateIndicator)
                    .opacity(settings.animateIndicator ? 1 : 0.5)
                    .padding(.bottom, 10)

                    Divider().opacity(0.55)

                    CompactToggleRow(
                        title: "Запускать при входе",
                        symbol: "person.crop.circle.badge.checkmark",
                        isOn: Binding(
                            get: { settings.launchAtLoginState == .on },
                            set: { _ in settings.toggleLaunchAtLogin() }
                        )
                    )
                }
                .frame(maxWidth: .infinity)
            }

            if let message = settings.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 20)
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

private struct CompactToggleRow: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 12)
    }
}

private struct DemoVisualConfiguration: Equatable {
    let sizeScale: Double
    let spacingScale: Double
    let animationsEnabled: Bool
    let animationStyle: IndicatorAnimationStyle
}

private struct InteractiveDemoZone: View {
    let indicators: [SpaceIndicatorKind]
    let currentActiveIndex: Int?
    let colors: [NSColor]
    let sizeScale: Double
    let spacingScale: Double
    let animationsEnabled: Bool
    let animationStyle: IndicatorAnimationStyle
    let setColor: (NSColor, Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeIndex = 0
    @State private var hoveredIndex: Int?
    @State private var paletteIndex: Int?
    @State private var paletteRequestID = UUID()

    private var previewColors: [NSColor] {
        colors.isEmpty
            ? Array(repeating: .controlAccentColor, count: 3)
            : colors
    }

    var body: some View {
        ZStack {
            IndicatorGlow(
                color: activeGlowColor,
                horizontalOffset: activeGlowHorizontalOffset
            )
            .animation(
                OrbitMotion.colorChange(
                    enabled: configuration.animationsEnabled,
                    reduceMotion: reduceMotion
                ),
                value: colorSignature
            )
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
                                .help(helpText(for: index))
                                .accessibilityLabel(helpText(for: index))
                        }
                    }
                }
                .frame(width: demoArtworkWidth, height: 45)
                .offset(y: 26)
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
                .transition(.liquidPalette)
                .zIndex(20)
            }

            TrackpadSwipeMonitor { direction in
                moveActive(by: direction)
            }
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
        }
        .onChange(of: requestedConfiguration) {
            paletteRequestID = UUID()
            withAnimation(paletteSpring) {
                paletteIndex = nil
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
    }

    private var demoScale: CGFloat {
        CGFloat(configuration.sizeScale) * 2.15
    }

    private var demoItemWidth: CGFloat {
        StatusItemArtwork.itemWidth(
            sizeScale: demoScale,
            spacingScale: CGFloat(configuration.spacingScale)
        )
    }

    private var demoStripWidth: CGFloat {
        CGFloat(indicators.count) * demoItemWidth
    }

    private var demoArtworkWidth: CGFloat {
        demoStripWidth
            + SyncedIndicatorArtworkView.horizontalOverflowPadding(
                for: demoScale,
                spacingScale: CGFloat(configuration.spacingScale)
            ) * 2
    }

    private var paletteSpring: Animation? {
        OrbitMotion.palette(
            enabled: configuration.animationsEnabled,
            reduceMotion: reduceMotion
        )
    }

    private var requestedConfiguration: DemoVisualConfiguration {
        DemoVisualConfiguration(
            sizeScale: sizeScale,
            spacingScale: spacingScale,
            animationsEnabled: animationsEnabled,
            animationStyle: animationStyle
        )
    }

    private var configuration: DemoVisualConfiguration {
        requestedConfiguration
    }

    private var colorSignature: String {
        previewColors.map(\.description).joined(separator: "|")
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

    private func color(for kind: SpaceIndicatorKind) -> NSColor {
        previewColors.indices.contains(kind.colorIndex)
            ? previewColors[kind.colorIndex]
            : .controlAccentColor
    }

    private func select(_ index: Int) {
        activeIndex = index
        let requestID = UUID()
        paletteRequestID = requestID

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

    private func helpText(for index: Int) -> String {
        switch indicators[index] {
        case .desktop:
            "Рабочий стол \(indicators[index].colorIndex + 1) — нажмите, чтобы изменить цвет"
        case .fullscreen:
            "Полноэкранное приложение — используется цвет связанного рабочего стола"
        }
    }

    private func synchronizeActiveIndex() {
        guard
            let currentActiveIndex,
            indicators.indices.contains(currentActiveIndex)
        else { return }
        activeIndex = currentActiveIndex
    }

}

private struct IndicatorGlow: View {
    let color: NSColor
    let horizontalOffset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [
                    Color(nsColor: color).opacity(0.22),
                    Color(nsColor: color).opacity(0.09),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 310
            )
            .frame(width: 620, height: 620)
            .blur(radius: 18)
            .position(
                x: proxy.size.width / 2 + horizontalOffset,
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
                .help(choice.title)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 39)
        .padding(.bottom, 9)
        .background(.regularMaterial, in: PaletteBubbleShape())
        .overlay {
            PaletteBubbleShape()
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .fixedSize()
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
            .blur(radius: (1 - progress) * 0.5)
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

private struct TrackpadSwipeMonitor: NSViewRepresentable {
    let onSwipe: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSwipe: onSwipe) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.view = view
        context.coordinator.onSwipe = onSwipe
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var onSwipe: (Int) -> Void
        private var monitor: Any?
        private var accumulatedDelta: CGFloat = 0
        private var didTrigger = false

        init(onSwipe: @escaping (Int) -> Void) {
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
                view.bounds.contains(
                    view.convert(event.locationInWindow, from: nil)
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
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout)
            DiscreteSlider(
                value: $value,
                steps: steps,
                accessibilityLabel: title
            )
            .frame(height: 25)
        }
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
