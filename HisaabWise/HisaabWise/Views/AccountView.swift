import UniformTypeIdentifiers
import CoreTransferable
import SwiftUI

/// Which of Account's four pages a row opens.
///
/// A wrapper rather than the bare `AccountScreen.Section`, for ``ExpenseCategoryRoute``'s reason:
/// `navigationDestination(for:)` matches on **type**, so a stack that also pushed a section-shaped value for
/// something else would find the wrong destination.
struct AccountDetailRoute: Hashable, Sendable {
    let section: AccountScreen.Section
}

/// Account, converted from the design's `account` document — level one, **the settings list**.
///
/// The profile card, four rows, the way out, and the data-subject export. One request (ADR-0020), and every
/// string on the screen arrived computed: the avatar's initials, the summary chip, each row's subtitle — including
/// "Changed 3 months ago", which is a date label and therefore the server's (invariant 6).
///
/// **Four rows and four pages**, pushed onto the stack the shell wraps this tab in. Each is opened with a
/// *section* and re-reads its row from the view model every time it draws, so a write that answers with a new
/// payload re-renders the page that is open (ADR-0020) — the shape Expenses' category detail already has.
///
/// **The design's `.version` line is not converted**, and that is a decision rather than an oversight: a build's
/// version comes from `Info.plist`, `AppConfig` is the one type that reads one, and it is not injected into the
/// view tree. Drawing it would mean either a second reader of `Bundle.main` — which two source scans forbid — or a
/// new environment value for one line of small print. Recorded in ADR-0038 with what it would cost.
struct AccountView: BaseView {
    /// Held rather than read from `@Environment`, so a test or a preview can construct the screen over a fixture
    /// transport. The five-tab shell puts one per tab in the environment.
    let viewModel: AccountViewModel

    /// Overridden because the server can answer with no screen at all, and a screen that supplied no empty copy
    /// would fall back to a default that says nothing about Account. `isEmpty` is `false` — a signed-in user
    /// always has an account.
    var stateCopy: StateCopy {
        StateCopy(empty: "account.empty")
    }

    /// **The chrome, and the page is ``AccountPage``.**
    ///
    /// The split is ADR-0033's finding, which every screen since has applied: `ImageRenderer` does not lay out the
    /// content of a `ScrollView`, so a render of the whole screen comes back as an empty ground — and a test
    /// asserting that it rendered passes on it.
    @ViewBuilder
    func loadedContent(_ screen: AccountScreen) -> some View {
        ScrollView {
            AccountPage(screen: screen, viewModel: viewModel)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        // One destination for all four pages, because they are one *kind* of thing — a settings page reached from
        // a row — and the `switch` inside it is where they differ.
        .navigationDestination(for: AccountDetailRoute.self) { route in
            page(route.section)
        }
        .hwToast(Self.copy(for: viewModel.notice), isPresented: viewModel.notice != nil)
        // The toast's lifetime is the screen's, not the component's (``HWToast``): it confirms something the user
        // just did, so it goes after a moment rather than waiting to be dismissed.
        .task(id: viewModel.notice) {
            guard viewModel.notice != nil else { return }
            try? await Task.sleep(for: .seconds(2.4))
            viewModel.dismissNotice()
        }
    }

    @ViewBuilder
    private func page(_ section: AccountScreen.Section) -> some View {
        switch section {
        case .personal: AccountPersonalPage(viewModel: viewModel)
        case .language: AccountLanguagePage(viewModel: viewModel)
        case .currency: AccountCurrencyPage(viewModel: viewModel)
        case .password: AccountPasswordPage(viewModel: viewModel)
        }
    }

    // MARK: - Mapping

    /// A row's glyph, from its section.
    ///
    /// The design's four 24×24 stroke drawings — a head and shoulders, a globe, a coin stack, a padlock — as the
    /// SF Symbols that draw the same things, for the reason `AppTab.systemImage` gives: Dynamic Type scaling and
    /// mirroring come free rather than four bespoke paths being shipped.
    nonisolated static func glyph(for section: AccountScreen.Section) -> String {
        switch section {
        case .personal: "person"
        case .language: "globe"
        case .currency: "banknote"
        case .password: "lock"
        }
    }

    /// What a row shows at its trailing edge.
    ///
    /// The payload's value for three of the four, and the **mask** for the password row — eight bullets, which are
    /// the design's own decoration rather than data. The server has no password to send and must never send a
    /// stand-in for one (``AccountScreen/Row/value``), so this is the one row whose value is copy.
    nonisolated static func value(for row: AccountScreen.Row) -> Text? {
        if row.section.masksValue { return Text("account.row.passwordMask") }
        return row.value.map { Text(verbatim: $0) }
    }

    /// Which words go with a landed write. The choice is the view model's; the sentence is the screen's
    /// (ADR-0011).
    nonisolated static func copy(for notice: AccountViewModel.Notice?) -> LocalizedStringResource? {
        switch notice {
        case .personalUpdated: "account.notice.personalUpdated"
        case .currencyChanged: "account.notice.currencyChanged"
        case .languageChanged: "account.notice.languageChanged"
        case .passwordChanged: "account.notice.passwordChanged"
        case nil: nil
        }
    }

    /// What a refused preference change or export says, and it says which of the two it was.
    ///
    /// A change that needs a connection is one to try again in a minute; one the server refused is not. Both are
    /// notices *beside* a screen that is fine rather than states the screen went into — see
    /// ``AccountViewModel/Refusal``.
    nonisolated static func copy(for reason: AccountViewModel.Refusal.Reason) -> LocalizedStringResource {
        switch reason {
        case .needsConnection: "account.refusal.needsConnection"
        case .refused: "account.refusal.refused"
        }
    }

    /// Every key this screen and its four pages render, for the suite that checks each has English behind it.
    ///
    /// A key with nothing behind it shows the user the key (ADR-0011), and the mapping functions above are exactly
    /// where one would go missing without a compiler complaining.
    static let copyKeys = [
        "account.empty",
        "account.eyebrow",
        "account.title",
        "account.tray.caption",
        "account.row.passwordMask",
        "account.export.action",
        "account.export.note",
        "account.export.fileName",
        "account.notice.personalUpdated",
        "account.notice.currencyChanged",
        "account.notice.languageChanged",
        "account.notice.passwordChanged",
        "account.refusal.needsConnection",
        "account.refusal.refused",
        "account.detail.unavailable",
        "account.personal.title",
        "account.personal.card",
        "account.personal.edit",
        "account.personal.done",
        "account.personal.username",
        "account.personal.salary",
        "account.personal.salary.unit",
        "account.personal.email",
        "account.personal.email.note",
        "account.personal.email.unverified",
        "account.personal.phone",
        "account.personal.phone.none",
        "account.personal.phone.dial",
        "account.personal.save",
        "account.personal.error.name",
        "account.personal.error.salary",
        "account.personal.error.phone",
        "account.personal.dialSheet.title",
        "account.personal.dialSheet.search",
        "account.language.title",
        "account.language.blurb",
        "account.language.search",
        "account.currency.title",
        "account.currency.blurb",
        "account.currency.search",
        "account.password.title",
        "account.password.step.one",
        "account.password.step.two",
        "account.password.step.three",
        "account.password.back",
        "account.password.current.heading",
        "account.password.current.blurb",
        "account.password.current.field",
        "account.password.questions.heading",
        "account.password.questions.blurb",
        "account.password.questions.support",
        "account.password.questions.answer",
        "account.password.new.heading",
        "account.password.new.blurb",
        "account.password.new.field",
        "account.password.new.confirm",
        "account.password.continue",
        "account.password.check",
        "account.password.submit",
        "account.password.error.currentMissing",
        "account.password.error.answerMissing",
        "account.password.error.tooShort",
        "account.password.error.mismatch",
        "account.password.error.currentRejected",
        "account.password.error.answersRejected",
    ]
}

/// Everything on the account root the reader looks at: the profile card, the four rows, the export, and the way
/// out.
///
/// **Separate from ``AccountView`` because `ImageRenderer` does not lay out the content of a `ScrollView`** — see
/// the note on `loadedContent`. It takes the screen it draws *and* the view model, because unlike Reports'
/// archive this page has controls on it: `ReportsArchivePage` is a record and this is a settings list.
struct AccountPage: View {
    @Environment(ThemeManager.self) private var theme

    let screen: AccountScreen
    let viewModel: AccountViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HWTopBar(eyebrow: "account.eyebrow", title: Text("account.title"))

            HWProfileHeader(
                initials: screen.profile.initials,
                name: screen.profile.displayName,
                email: screen.profile.email,
                summary: screen.profile.summaryLabel
            )

            rows

            // The design's `margin-top:auto` puts the way out at the bottom of the screen. Here it is at the
            // bottom of the *content*, which is the same place on a phone and the honest one on a page that
            // scrolls: a control pinned below a scrolling list is a control that covers the list.
            export

            LogoutControl()
        }
    }

    /// `.bubble` — the four rows, in the order the payload lists them (ADR-0020).
    private var rows: some View {
        HWSettingsTray(caption: "account.tray.caption") {
            ForEach(screen.rows) { row in
                // A `NavigationLink` rather than a button plus a path append: the row *is* the destination, and
                // the shell already wraps this tab in a stack.
                NavigationLink(value: AccountDetailRoute(section: row.section)) {
                    HWRowLabel(
                        systemImage: AccountView.glyph(for: row.section),
                        name: Text(verbatim: row.name),
                        subtitle: Text(verbatim: row.hint),
                        value: AccountView.value(for: row)
                    )
                }
                .buttonStyle(HWPressStyle())
                // Read as one control: the name, the subtitle, and the value in one swipe. Four stops for one row
                // is the focus-order failure ADR-0012 is about.
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The UAE PDPL access right (Product Spec §8), as a control rather than a fifth row.
    ///
    /// **The design has no such control**, and a fifth row inside `.bubble` would claim to be one of the design's
    /// four. So it sits with the other thing on this screen that is about the account rather than a setting of
    /// it — the way out — and says in a line under itself what it does.
    @ViewBuilder
    private var export: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let data = viewModel.exportedData {
                // **A share sheet rather than a file the app wrote somewhere.** The bytes are every figure, entry
                // and address this system holds about one person; the user chooses where they go and the app keeps
                // no second copy (ADR-0014, ADR-0038).
                ShareLink(
                    item: AccountExport(data: data),
                    preview: SharePreview(Text("account.export.action"))
                ) {
                    HWButtonFace("account.export.action", variant: .soft, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(HWPressStyle())
                // Handing the bytes to the sheet is the last thing that needs them.
                .onDisappear { viewModel.discardExport() }
            } else {
                HWButton(
                    "account.export.action",
                    variant: .soft,
                    systemImage: "arrow.down.doc",
                    state: viewModel.isExporting ? .inFlight : .ready
                ) {
                    Task { await viewModel.exportMyData() }
                }
            }

            Text("account.export.note")
                .font(.hw(.micro))
                .foregroundStyle(theme.palette.surface.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            // **The export's own refusal, not whichever was last.** With one bare reason on the view model, a
            // failed currency change drew its sentence under this button — which is what review found.
            AccountRefusalNote(reason: viewModel.refusal(about: .export))
        }
    }
}

/// The export, as something a share sheet can carry.
///
/// **A `Transferable` over the bytes rather than a file the app wrote.** `ShareLink` needs a value and a suggested
/// name, and this gives it both without the export ever touching the file system — which for a document holding
/// one person's entire financial history is the whole point: there is no copy left in a temporary directory for
/// something else to find, and nothing to remember to delete (ADR-0014).
///
/// It lives in `Views` rather than `Models` because a transfer representation is presentation: what it decides is
/// how the bytes leave the app, not what they are. The client never decodes them (``APIClient/bytes(at:)``).
struct AccountExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            // Not dated, deliberately: the client owns no calendar (invariant 6), and a file named from the device
            // clock would be a date this app is not allowed to work out. What the export contains is the server's
            // to timestamp, inside the document.
            .suggestedFileName(String(localized: "account.export.fileName"))
    }
}

#if DEBUG
#Preview("Account — the settings list") {
    NavigationStack { AccountView(viewModel: .previewINR) }.hwTheme()
}

#Preview("Account — email unverified, no phone number") {
    NavigationStack { AccountView(viewModel: .previewUnverified) }.hwTheme()
}

#Preview("Account — offline") {
    NavigationStack { AccountView(viewModel: .previewOffline) }.hwTheme()
}

#Preview("Account — the endpoint is not written yet (501)") {
    NavigationStack { AccountView(viewModel: .previewNotImplemented) }.hwTheme()
}

#Preview("Account — Arabic, right to left") {
    NavigationStack { AccountView(viewModel: .previewINR) }
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("Account — AX5") {
    NavigationStack { AccountView(viewModel: .previewINR) }
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
