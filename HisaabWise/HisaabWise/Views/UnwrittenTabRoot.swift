import SwiftUI

/// A tab whose screen has not been written yet: the real chrome, the real state machinery, and one sentence
/// where the screen goes.
///
/// The shell is five tabs and four of the five screens are other tickets — Expenses (#18), Learn (#19),
/// Reports (#21), Account (#23). This is what stands in until each arrives, and what it is careful to be is
/// **honest**: it says the screen is not built, rather than fetching a route the backend has not written and
/// showing "Something went wrong" (see ``UnwrittenScreenViewModel``).
///
/// It is a full ``BaseView`` conformance rather than a plain `View`, which is issue #5's criterion — every tab
/// root renders its state through ``StateView`` — and it is what makes the swap cheap: each of those four
/// issues writes a screen and deletes one `case` from ``AppShell``.
///
/// The `footer` slot exists for Account, which carries ``LogoutControl``. A `ViewBuilder` rather than a value,
/// for the reason ``HWTopBar`` gives for its trailing slot: it holds a *control*, and a placeholder that took
/// one as data would be picking which control.
struct UnwrittenTabRoot<Footer: View>: BaseView {
    @Environment(ThemeManager.self) private var theme

    let tab: AppTab
    let viewModel: UnwrittenScreenViewModel
    @ViewBuilder let footer: Footer

    /// The same sentence as the loaded content, because for a screen that does not exist yet "there is
    /// nothing to show" and "this is not built" are the same fact. It is one key rather than two so the
    /// translation pass has one string to throw away later.
    var stateCopy: StateCopy {
        StateCopy(empty: "shell.unwritten.note")
    }

    @ViewBuilder
    func loadedContent(_ value: NothingYet) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HWTopBar(title: Text(tab.title))

            Text("shell.unwritten.note")
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            footer
        }
        .padding(20)
    }
}

extension UnwrittenTabRoot where Footer == EmptyView {
    /// A placeholder with nothing under it, which is three of the four.
    init(tab: AppTab, viewModel: UnwrittenScreenViewModel) {
        self.init(tab: tab, viewModel: viewModel, footer: { EmptyView() })
    }
}

#if DEBUG
// A fresh view model in each, rather than one with its state set by hand: the chrome's `.task` loads it, and
// `UnwrittenScreenViewModel` answers immediately — so the preview exercises the same path the app does, and
// nothing writes `state` from outside `load()`.
#Preview("An unwritten tab") {
    UnwrittenTabRoot(tab: .expenses, viewModel: UnwrittenScreenViewModel()).hwTheme()
}

#Preview("Account — the one that carries the way out") {
    UnwrittenTabRoot(tab: .account, viewModel: UnwrittenScreenViewModel()) { LogoutControl() }
        .hwTheme()
}

#Preview("RTL") {
    UnwrittenTabRoot(tab: .reports, viewModel: UnwrittenScreenViewModel())
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("AX5") {
    UnwrittenTabRoot(tab: .learn, viewModel: UnwrittenScreenViewModel())
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
