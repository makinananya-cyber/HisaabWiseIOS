import SwiftUI

/// What each tab is called and what it is drawn as.
///
/// Here rather than on the `Models` type for two reasons: copy belongs in the presentation layer, where the
/// localisation scans look for the keys, and a glyph is a design decision. The design's tab icons are
/// 24×24 stroke drawings; each maps to the SF Symbol that draws the same thing, so the app gets Dynamic Type
/// scaling and mirroring for free rather than shipping five bespoke paths.
extension AppTab {
    var title: LocalizedStringResource {
        switch self {
        case .home: "shell.tab.home"
        case .expenses: "shell.tab.expenses"
        case .learn: "shell.tab.learn"
        case .reports: "shell.tab.reports"
        case .account: "shell.tab.account"
        }
    }

    /// The design's icon, as the symbol that draws it:
    ///
    /// | Design | Here |
    /// |---|---|
    /// | a house outline | `house` |
    /// | a card with a stripe and a stub | `creditcard` |
    /// | an open book with a spine | `book` |
    /// | three bars on an axis | `chart.bar` |
    /// | a head and shoulders | `person` |
    ///
    /// Outline weights throughout, matching the design's `stroke-width:1.9` — the `.fill` variants are what a
    /// selected tab would use in a different app, and this one marks selection with colour, as the design's
    /// `.tab.on` does. None of the five encodes a direction, which `AppShellTests` asserts against the values
    /// as well as `LocalisationTests` asserting it against the source.
    var systemImage: String {
        switch self {
        case .home: "house"
        case .expenses: "creditcard"
        case .learn: "book"
        case .reports: "chart.bar"
        case .account: "person"
        }
    }
}

/// The app you can navigate: five tabs, a navigation stack each, and no other way between them.
///
/// **A `TabView`, not the design's `.tabbar`.** Converting that CSS would mean re-implementing a system
/// container — the safe-area inset, the material, the selection semantics, the VoiceOver "tab 2 of 5" — which
/// Rule 1 rules out and which would be worse at all four. So the design's *decisions* are converted and its
/// markup is not: the label sits under the glyph, every tab is always visible, and selection is marked with
/// the design's `--galaxy` through `surface.ink`.
///
/// **One thing the design asks for that a `TabView` will not give.** The design's unselected tabs are
/// `--ink-3`; SwiftUI exposes the selected tint and leaves the unselected colour to the system, and reaching
/// it means `UITabBar.appearance()` — a UIKit global, and a global at that. The system grey is close enough
/// to `--ink-3` to be worth less than a UIKit dependency in a pure-SwiftUI app (Rule 1), and it is recorded
/// here rather than silently accepted.
///
/// **A `NavigationStack` per tab**, which is what makes each tab keep its own place: a push on Reports does
/// not follow the user to Learn, and coming back to Reports comes back to where they were.
struct AppShell: View {
    @Environment(ThemeManager.self) private var theme

    /// Made at the composition root and injected, so a tab keeps its state across a switch away and back
    /// (issue #5).
    @Environment(TabViewModels.self) private var viewModels

    /// Read for one thing: whether the signed-in account has verified its email (#15).
    @Environment(SessionCoordinator.self) private var session

    /// Which tab is showing. `@State`, so it survives a re-render and nothing else has to own it — the
    /// selection is not app state, it is where the user is.
    @State private var selection: AppTab = .home

    var body: some View {
        VStack(spacing: 0) {
            if Self.showsVerificationBanner(for: session.user) {
                verificationBanner
            }

            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            // Over `AppTab.allCases`, so the tab bar cannot come to disagree with the set about how many tabs
            // there are or what order they are in. The five roots still differ, and `root(_:)` is where.
            ForEach(AppTab.allCases, id: \.self) { tab in
                Tab(value: tab) { root(tab) } label: { label(tab) }
            }
        }
        // The design's `.tab.on{color:var(--galaxy)}`, which on the in-app surface is the ink role.
        .tint(theme.palette.surface.ink)
    }

    /// **Whether to show the "verify your email" banner** (#15).
    ///
    /// `nil` shows nothing: the identity has not come back yet, and a banner that flashed on every cold launch
    /// before `GET /v1/me` answered would be an accusation the app then withdraws. An unverified account
    /// **can use the app** — this is a reminder, not a gate, which is why it is a strip above the tabs and not a
    /// screen in front of them.
    ///
    /// A function over the value rather than a computed property, so the rule is assertable without a session:
    /// there are three inputs and all three matter.
    static func showsVerificationBanner(for user: SessionUser?) -> Bool {
        guard let user else { return false }
        return !user.emailVerified
    }

    /// The strip itself. It carries no action: verification happens in the email, and ADR-0008's foreground
    /// revalidation is what makes the banner disappear when the user comes back from Safari having tapped the
    /// link — a "resend" control belongs to the Account screen (#17), which owns the account's own settings.
    private var verificationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope.badge")
                .font(.hw(.body))
                .foregroundStyle(theme.palette.accent.base)
                .accessibilityHidden(true)

            Text("shell.verifyEmail")
                .font(.hw(.caption))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(theme.palette.accent.tint)
        // One element, read as a whole, and **not** a header: it is a notice above the tabs rather than the
        // title of anything (ADR-0012).
        .accessibilityElement(children: .combine)
    }

    /// One stack per tab, wrapped here rather than inside each screen: a screen that owned its own
    /// `NavigationStack` would be a screen that could be pushed onto another one.
    @ViewBuilder
    private func root(_ tab: AppTab) -> some View {
        NavigationStack {
            switch tab {
            case .home:
                HomeView(
                    viewModel: viewModels.home,
                    // The two places Home sends the user, both of them **tabs** — so the shell supplies them
                    // rather than Home reaching for a selection it does not own (#17).
                    onAddExpense: { selection = .expenses },
                    onContinueLearning: { selection = .learn }
                )
            case .expenses: ExpensesView(viewModel: viewModels.expenses)
            case .learn: UnwrittenTabRoot(tab: tab, viewModel: viewModels.learn)
            case .reports: UnwrittenTabRoot(tab: tab, viewModel: viewModels.reports)
            // Account carries the way out, because the design puts it there. It is the only thing on any of
            // the four unwritten screens that is real, and it is here rather than on a debug affordance
            // because "log out actually ends the session" is one of this issue's criteria.
            case .account:
                UnwrittenTabRoot(tab: tab, viewModel: viewModels.account) { LogoutControl() }
            }
        }
    }

    /// The glyph and the word, which is what the design's tab is: an icon over a 9.5px label. VoiceOver reads
    /// the label and the platform adds the position and the selected trait, so there is nothing to add here —
    /// a `.accessibilityLabel` would replace "Home, tab, 1 of 5" with "Home".
    private func label(_ tab: AppTab) -> some View {
        Label { Text(tab.title) } icon: { Image(systemName: tab.systemImage) }
    }
}

#if DEBUG
/// The shell over fixtures, which is the only way to look at it until sign-in ships (#14): the app itself
/// launches signed out, and `RootView` draws Landing.
@MainActor
private func previewViewModels() -> TabViewModels {
    TabViewModels(home: .previewINRSalary, expenses: .previewINR)
}

#Preview("The shell — five tabs") {
    AppShell()
        .environment(previewViewModels())
        .hwTheme()
}

#Preview("RTL — the tabs run the other way") {
    AppShell()
        .environment(previewViewModels())
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("AX5 — the tab bar grows and the labels wrap") {
    AppShell()
        .environment(previewViewModels())
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
