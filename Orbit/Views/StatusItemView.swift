import AppKit
import SwiftUI

struct StatusItemView: View {
    @ObservedObject var viewModel: SpaceViewModel

    var body: some View {
        SpaceDotsView(
            count: viewModel.spaceCount,
            activeIndex: viewModel.activeIndex
        ) { _ in }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            OrbitL10n.text(
                "accessibility.desktops",
                fallback: "Desktops"
            )
        )
    }

    static func preferredWidth(for count: Int) -> CGFloat {
        StatusItemArtwork.preferredWidth(for: count)
    }
}

struct SpaceDotsView: View {
    let count: Int
    let activeIndex: Int?
    let action: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var liquidPhase = LiquidPhase.rest
    @State private var flowDirection: CGFloat = 0
    @State private var flowTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(0..<max(count, 1), id: \.self) { index in
                    SpaceDotButton(
                        index: index,
                        isActive: index == activeIndex,
                        reduceMotion: reduceMotion,
                        action: action
                    )
                }
            }

            if let activeIndex, (0..<max(count, 1)).contains(activeIndex) {
                ActiveSpacePill(
                    liquidPhase: liquidPhase,
                    flowDirection: flowDirection,
                    reduceMotion: reduceMotion
                )
                .frame(width: 14, height: 20)
                .offset(x: CGFloat(activeIndex) * 14)
                .animation(
                    OrbitMotion.indicatorChange(
                        style: .seamless,
                        enabled: true,
                        reduceMotion: reduceMotion
                    ),
                    value: activeIndex
                )
                .allowsHitTesting(false)
            }
        }
        .onChange(of: activeIndex) { oldValue, newValue in
            guard newValue != nil else { return }
            if let oldValue, let newValue {
                flowDirection = newValue > oldValue ? 1 : -1
            }
            animateFlow()
        }
        .onDisappear {
            flowTask?.cancel()
            flowTask = nil
        }
    }

    private func animateFlow() {
        flowTask?.cancel()

        guard !reduceMotion else {
            liquidPhase = .rest
            return
        }

        withAnimation(OrbitMotion.flowStretch(reduceMotion: reduceMotion)) {
            liquidPhase = .stretch
        }

        flowTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(90))
            } catch {
                return
            }
            withAnimation(OrbitMotion.flowSquash(reduceMotion: reduceMotion)) {
                liquidPhase = .squash
            }
            do {
                try await Task.sleep(for: .milliseconds(75))
            } catch {
                return
            }
            withAnimation(OrbitMotion.flowSettle(reduceMotion: reduceMotion)) {
                liquidPhase = .rest
            }
        }
    }
}

private struct ActiveSpacePill: View {
    let liquidPhase: LiquidPhase
    let flowDirection: CGFloat
    let reduceMotion: Bool

    var body: some View {
        Capsule(style: .continuous)
            // A concrete system accent color does not change when the menu bar
            // flips between its light and dark appearances.
            .fill(Color(nsColor: .controlAccentColor))
            .frame(
                width: reduceMotion ? 12 : liquidPhase.size.width,
                height: reduceMotion ? 7 : liquidPhase.size.height
            )
            .offset(
                x: reduceMotion
                    ? 0
                    : liquidPhase.directionalOffset * flowDirection
            )
    }
}

private enum LiquidPhase {
    case rest
    case stretch
    case squash

    var size: CGSize {
        switch self {
        case .rest: CGSize(width: 12, height: 7)
        case .stretch: CGSize(width: 19.5, height: 5.8)
        case .squash: CGSize(width: 10.5, height: 7.8)
        }
    }

    var directionalOffset: CGFloat {
        switch self {
        case .rest: 0
        case .stretch: -1.8
        case .squash: 0.8
        }
    }
}

private struct SpaceDotButton: View {
    let index: Int
    let isActive: Bool
    let reduceMotion: Bool
    let action: (Int) -> Void

    @State private var isHovered = false

    var body: some View {
        Button { action(index) } label: {
            ZStack {
                Circle()
                    .fill(.primary.opacity(0.28))
                    .frame(width: 4.5, height: 4.5)
                    .scaleEffect(isActive ? 0.45 : 1)
                    .opacity(isActive ? 0 : 1)
            }
            .frame(width: 14, height: 20)
            .background {
                Circle()
                    .fill(.primary.opacity(isHovered ? 0.07 : 0))
                    .frame(width: 14, height: 14)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressedButtonStyle(scale: 0.97))
        .onHover { isHovered = $0 }
        .accessibilityLabel(
            OrbitL10n.format(
                "accessibility.desktop",
                fallback: "Desktop %lld",
                index + 1
            )
        )
        .accessibilityValue(
            OrbitL10n.text(
                isActive
                    ? "accessibility.desktop.selected"
                    : "accessibility.desktop.unselected",
                fallback: isActive ? "Selected" : "Not selected"
            )
        )
        .animation(
            OrbitMotion.press(reduceMotion: reduceMotion),
            value: isActive
        )
    }
}
