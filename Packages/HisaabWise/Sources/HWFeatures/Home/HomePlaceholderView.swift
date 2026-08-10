import HWCore
import SwiftUI

/// The far end of the walking skeleton: a canned HTTP payload, decoded through the real client, shown
/// as text.
///
/// A placeholder in the literal sense — Home's actual content is Phase 2. What it establishes is that
/// the only thing a view does with money is render the server's ``Money/display`` string, and that
/// every screen goes through ``LoadState``.
///
/// The four non-loaded states are drawn inline here. They move to `HWDesignSystem`'s single
/// `StateView`, with its own copy and its own error-code mapping, when that arrives.
public struct HomePlaceholderView: View {
    private let store: HomeStore

    public init(store: HomeStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch store.state {
            case .loading:
                ProgressView()
            case .empty:
                Text("home.empty", bundle: .module)
            case .offline:
                // Offline is a supported mode, not a fault — so it does not read as one.
                Text("home.offline", bundle: .module)
            case .failed:
                // The code is deliberately not rendered: the copy for it is the design system's job,
                // and the server's own message is never shown (ADR-0016).
                Text("home.failed", bundle: .module)
            case .loaded(let budget):
                Text("home.income.label", bundle: .module)
                    .font(.subheadline)
                Text(budget.income.display)
                    .font(.largeTitle)
                    // Composed from a catalogue format string plus the server's display string, so
                    // the sentence is translatable and the figure is never reformatted (ADR-0012).
                    .accessibilityLabel(
                        Text("home.income.accessibilityLabel \(budget.income.display)", bundle: .module)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .task { await store.load() }
    }
}
