import AppKit
import SwiftUI

struct StatusItemView: View {
    @ObservedObject var viewModel: SpaceViewModel

    var body: some View {
        SpaceDotsView(
            count: viewModel.spaceCount,
            activeIndex: viewModel.activeIndex
        ) { index in
            Task { await viewModel.select(index) }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("accessibility.workspaces"))
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
                .frame(width: StatusItemArtwork.itemWidth, height: 22)
                .offset(x: CGFloat(activeIndex) * StatusItemArtwork.itemWidth)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.08)
                        : .spring(response: 0.25, dampingFraction: 0.82, blendDuration: 0.04),
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

        withAnimation(.easeOut(duration: 0.075)) {
            liquidPhase = .stretch
        }

        flowTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(90))
            } catch {
                return
            }
            withAnimation(.spring(response: 0.14, dampingFraction: 0.68)) {
                liquidPhase = .squash
            }
            do {
                try await Task.sleep(for: .milliseconds(75))
            } catch {
                return
            }
            withAnimation(.spring(response: 0.16, dampingFraction: 0.82)) {
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
                width: reduceMotion ? StatusItemArtwork.scaled(12) : liquidPhase.size.width,
                height: reduceMotion ? StatusItemArtwork.scaled(7) : liquidPhase.size.height
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
        case .rest:
            CGSize(
                width: StatusItemArtwork.scaled(12),
                height: StatusItemArtwork.scaled(7)
            )
        case .stretch:
            CGSize(
                width: StatusItemArtwork.scaled(19.5),
                height: StatusItemArtwork.scaled(5.8)
            )
        case .squash:
            CGSize(
                width: StatusItemArtwork.scaled(10.5),
                height: StatusItemArtwork.scaled(7.8)
            )
        }
    }

    var directionalOffset: CGFloat {
        switch self {
        case .rest: 0
        case .stretch: StatusItemArtwork.scaled(-1.8)
        case .squash: StatusItemArtwork.scaled(0.8)
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
                    .frame(
                        width: StatusItemArtwork.scaled(4.5),
                        height: StatusItemArtwork.scaled(4.5)
                    )
                    .scaleEffect(isActive ? 0.45 : 1)
                    .opacity(isActive ? 0 : 1)
            }
            .frame(width: StatusItemArtwork.itemWidth, height: 22)
            .background {
                Circle()
                    .fill(.primary.opacity(isHovered ? 0.07 : 0))
                    .frame(
                        width: StatusItemArtwork.itemWidth,
                        height: StatusItemArtwork.itemWidth
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressedButtonStyle(scale: 0.97))
        .onHover { isHovered = $0 }
        .help(
            L10n.format(
                isActive ? "help.currentWorkspace" : "help.switchWorkspace",
                index + 1
            )
        )
        .accessibilityLabel(L10n.format("accessibility.workspace", index + 1))
        .accessibilityValue(
            L10n.string(
                isActive ? "accessibility.selected" : "accessibility.unselected"
            )
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.1),
            value: isActive
        )
    }
}
