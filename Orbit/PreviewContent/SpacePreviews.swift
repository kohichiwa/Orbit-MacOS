#if DEBUG
import SwiftUI

private struct SpacePreviewScenario: View {
    @StateObject private var viewModel: SpaceViewModel

    init(count: Int, activeIndex: Int?) {
        let snapshot = SpaceSnapshot(
            identifiers: (0..<count).map { Int64($0 + 1) },
            activeIndex: activeIndex
        )
        _viewModel = StateObject(wrappedValue: SpaceViewModel(previewSnapshot: snapshot))
    }

    var body: some View {
        StatusItemView(viewModel: viewModel)
            .padding(8)
            .background(.bar)
    }
}

struct SpacePreviews: PreviewProvider {
    @MainActor static var previews: some View {
        Group {
            SpacePreviewScenario(count: 1, activeIndex: 0)
                .previewDisplayName("Один Space")
            SpacePreviewScenario(count: 4, activeIndex: 1)
                .preferredColorScheme(.light)
                .previewDisplayName("Светлая тема")
            SpacePreviewScenario(count: 6, activeIndex: 4)
                .preferredColorScheme(.dark)
                .previewDisplayName("Тёмная тема")
            SpacePreviewScenario(count: 10, activeIndex: 7)
                .previewDisplayName("Много Spaces")
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
