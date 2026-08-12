import SwiftUI
@testable import HisaabWise

/// The four snapshots, and **exactly four**.
///
/// ADR-0013 fixes the number as well as the subjects: "the snapshot suite stays deliberately small and pinned.
/// An unpinned or sprawling snapshot suite goes flaky, and a flaky gate gets deleted rather than fixed." So the
/// set is a closed enum, `SnapshotSuiteTests` asserts its size, and adding a fifth is a decision somebody has
/// to make on purpose rather than a file somebody adds.
///
/// Each one earns its place by covering a class of regression that nothing else here can see:
///
/// | Case | What only a snapshot catches |
/// |---|---|
/// | ``populated`` | a screen drawing real figures — the layout of a loaded tab |
/// | ``empty`` | the empty state, which is copy and a symbol and nothing else |
/// | ``rightToLeft`` | mirroring, which is a *layout* problem and is found by looking (ADR-0011) |
/// | ``accessibilitySize`` | text at AX3, where the design's fixed heights would clip (ADR-0012) |
///
/// The views are built over the **fixture corpus**, so a payload that drifts from the API fails the decoding
/// tests *and* changes these pictures — which is ADR-0013's one-corpus argument reaching the baselines.
enum SnapshotCase: String, CaseIterable, Sendable {
    /// Home over the standing rupee fixture.
    case populated = "home-populated"

    /// **Reports' empty state** — an account whose first month has not closed yet (#21).
    ///
    /// It is a real screen's empty state now rather than a generic one: `ReportsViewModel.isEmpty(_:)` says so
    /// for an archive with no years in it, which makes this the first `LoadState.empty` the app can actually
    /// reach. Expenses was the other candidate and turned out not to be one — its first run keeps all seven
    /// categories and is `.loaded`.
    ///
    /// **Still drawn through ``StateView`` rather than as a whole screen, and that is not a shortcut.** A
    /// `BaseView` render lands on `.loading`: the chrome supplies `.task { load() }` and `ImageRenderer` yields
    /// to the main actor once before capturing, so photographing `ReportsView` here would photograph the spinner
    /// — which is exactly what `SnapshotSuiteTests` uses this case to prove is *not* happening. The copy is the
    /// screen's own, so the baseline is Reports' sentence.
    case empty = "reports-empty"

    /// Home under Arabic, driven through `LanguageManager` so the snapshot exercises the injection the app
    /// runs rather than a layout direction set by hand.
    case rightToLeft = "home-arabic"

    /// Home at AX3. Not AX5: AX3 is where the design's fixed-height controls first fail, and a baseline at AX5
    /// is a picture of wrapped text rather than of a layout decision.
    case accessibilitySize = "home-ax3"

    /// Whether the case draws a screen whose figures arrive from a request.
    ///
    /// The three that do can only be photographed **loaded** by a hosted capture: a `BaseView` renders through
    /// a chrome that supplies `.task { load() }`, and `ImageRenderer` yields to the main actor once before it
    /// captures — so its pixels are the spinner however loaded the view model was a moment earlier
    /// (`CONTEXT.md`). That is one of the two reasons this suite needs `swift-snapshot-testing` rather than a
    /// hand-rolled comparison; see `SnapshotSuiteTests`.
    var drawsAFetchedScreen: Bool {
        switch self {
        case .populated, .rightToLeft, .accessibilitySize: true
        case .empty: false
        }
    }

    /// The view to photograph.
    @MainActor
    func view() -> AnyView {
        switch self {
        case .populated:
            AnyView(home().hwTheme())

        case .empty:
            AnyView(
                StateView(
                    state: LoadState<ReportsScreen>.empty,
                    copy: ReportsView(viewModel: .previewEmpty).stateCopy,
                    reload: {}
                ) { _ in
                    EmptyView()
                }
                // The frame the chrome applies, which is what decides where a short column sits.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .hwTheme()
            )

        case .rightToLeft:
            AnyView(home().hwTheme().hwLanguage(LanguageManager(selected: .arabic)))

        case .accessibilitySize:
            AnyView(home().hwTheme().dynamicTypeSize(.accessibility3))
        }
    }

    /// Home over the corpus's standing rupee payload — the default preview, so that a hardcoded `AED 8,000`
    /// shows up in a baseline as well as in Xcode (defect D1, ADR-0013).
    @MainActor
    private func home() -> HomeView {
        HomeView(viewModel: .previewINRSalary)
    }
}
