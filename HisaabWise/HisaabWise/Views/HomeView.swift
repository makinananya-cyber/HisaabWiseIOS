import SwiftUI

/// The far end of the walking skeleton: a canned HTTP payload, decoded through the real client, shown
/// as text.
///
/// A placeholder in the literal sense — Home's actual content is Phase 2. What it establishes is that
/// the only thing a view does with money is render the server's ``Money/display`` string, and that
/// every screen goes through ``LoadState``.
///
/// The four non-loaded states are drawn inline here. They move to `DesignSystem`'s single `StateView`,
/// with its own copy and its own error-code mapping, when that arrives.
struct HomeView: View {
    /// Held by the view rather than read from `@Environment` so that a test can construct the view
    /// over a fixture transport. The five-tab shell puts one view model per tab in the environment.
    private let viewModel: HomeViewModel

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch viewModel.state {
            case .loading:
                ProgressView()
            case .empty:
                Text("home.empty")
            case .offline:
                // Offline is a supported mode, not a fault — so it does not read as one.
                Text("home.offline")
            case .failed:
                // The code is deliberately not rendered: the copy for it is the design system's job,
                // and the server's own message is never shown (ADR-0016).
                Text("home.failed")
            case .loaded(let budget):
                Text("home.income.label")
                    .font(.subheadline)
                Text(verbatim: budget.income.display)
                    .font(.largeTitle)
                    // Composed from a catalogue format string plus the server's display string, so
                    // the sentence is translatable and the figure is never reformatted (ADR-0012).
                    .accessibilityLabel(Text("home.income.accessibilityLabel \(budget.income.display)"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .task { await viewModel.load() }
    }
}

#if DEBUG
// The view models these use are assembled in `Fixtures/PreviewViewModels.swift` — a view has no
// business building a client, and `LayeringTests` holds this file to that.
#Preview("Home — INR salary") {
    HomeView(viewModel: .previewINRSalary)
}

#Preview("Home — offline") {
    HomeView(viewModel: .previewOffline)
}
#endif
