import SwiftUI

/// The far end of the walking skeleton: a canned HTTP payload, decoded through the real client, shown as
/// text.
///
/// A placeholder in the literal sense — Home's actual content is Phase 2. What it establishes is that
/// the only thing a view does with money is render the server's ``Money/display`` string, and that every
/// screen goes through ``LoadState``.
///
/// It is also the first ``BaseView``, and so the shape every later screen copies: declare the view model,
/// declare the copy for the states with nothing in them, draw the loaded case. The four non-loaded states
/// it used to draw inline are ``StateView``'s now, and the error mapping it used to carry is
/// ``BaseViewModel/load()``'s.
struct HomeView: BaseView {
    @Environment(ThemeManager.self) private var theme

    /// Held rather than read from `@Environment` so that a test can construct the view over a fixture
    /// transport. The five-tab shell puts one per tab in the environment.
    let viewModel: HomeViewModel

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    /// Home overrides only `empty`. Offline, loading, and retry read the same here as anywhere, and
    /// twenty rewordings of "you're offline" is the outcome ADR-0016 exists to prevent.
    var stateCopy: StateCopy {
        StateCopy(empty: "home.empty")
    }

    @ViewBuilder
    func loadedContent(_ budget: BudgetSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("home.income.label")
                .font(.hw(.caption))
                .foregroundStyle(theme.palette.surface.inkSecondary)
            Text(verbatim: budget.income.display)
                .font(.hw(.display))
                .foregroundStyle(theme.palette.surface.ink)
                // Composed from a catalogue format string plus the server's display string, so the
                // sentence is translatable and the figure is never reformatted (ADR-0012).
                .accessibilityLabel(Text("home.income.accessibilityLabel \(budget.income.display)"))
        }
        // No `.frame(maxWidth:)` here: the chrome already sizes and aligns what it is handed.
        .padding()
    }
}

#if DEBUG
// The view models these use are assembled in `Fixtures/PreviewViewModels.swift` — a view has no
// business building a client, and `LayeringTests` holds this file to that.
#Preview("Home — INR salary") {
    HomeView(viewModel: .previewINRSalary).hwTheme()
}

#Preview("Home — offline") {
    HomeView(viewModel: .previewOffline).hwTheme()
}
#endif
