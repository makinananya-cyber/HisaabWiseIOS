import SwiftUI

/// Level two of the design's `account` document — the four pages behind the four rows.
///
/// **None of them is a ``BaseView``**, and that is the right shape: they are pushed pages over a screen that is
/// already loaded, so they have no request of their own and no four empty-handed states to draw. Each re-reads
/// what it needs from the view model every time it draws, so a write that answers with a new payload re-renders
/// the page that is open (ADR-0020) — the shape `ExpenseCategoryView` already has.
///
/// **The design's `.backbar` is not converted.** The stack's own back button is the affordance, which is the call
/// `ArticleView` and `ReportsMonthView` both make, and the title goes in the navigation bar.
///
/// What each page does when it has nothing to draw is say so. A write that failed offline replaces `state` with
/// `LoadState.offline` (ADR-0019), and the page pushed on top of it stays on screen with no payload behind it — so
/// the honest thing is one sentence and the back button, rather than a blank page or a crash on an optional.
struct AccountDetailUnavailable: View {
    var body: some View {
        HWBanner("account.detail.unavailable", systemImage: "arrow.trianglehead.counterclockwise", tone: .refusal)
            .padding(.vertical, 14)
    }
}

// MARK: - Personal information

/// The design's `#pi` card — four lines, three editable, and the one that is not.
///
/// **Email is locked** (invariant 4). It has no field in edit mode, no field in the request
/// (``PersonalDetailsUpdate``), and a sentence under it saying why. The design's own copy carries the reason and
/// it is converted verbatim: "it is how we verify it is you".
///
/// **Edit mode is the design's `.editbtn`**, in the navigation bar where the design's `.backbar` puts it. Its two
/// words are the design's `.txt-edit` / `.txt-done` — the same control saying which state it is in, which is why
/// it is ``HWEditButton`` and not two buttons.
struct AccountPersonalPage: View {
    // **No `@Environment(ThemeManager.self)`, deliberately.** Every colour on this page belongs to a component, and
    // an unused read of a non-optional observable object is not free: SwiftUI resolves it when the view updates, so
    // a page that declared one it never read would trap rather than read nothing (`CONTEXT.md`, ADR-0036).
    let viewModel: AccountViewModel

    /// The country sheet, which is the one thing on this page the design draws as a sheet rather than a page.
    @State private var isChoosingDialCode = false

    /// **The chrome, and the card is ``AccountPersonalCard``.**
    ///
    /// The split is ADR-0033's finding, which every screen since has applied and which photographing this page
    /// found again: `ImageRenderer` does not lay out the content of a `ScrollView`, so a render of the page comes
    /// back as an empty ground — and a test asserting that it rendered passes on it.
    var body: some View {
        ScrollView {
            AccountPersonalCard(viewModel: viewModel, onChangeDialCode: { isChoosingDialCode = true })
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(Text("account.personal.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HWEditButton(
                    viewModel.isEditingPersonal ? "account.personal.done" : "account.personal.edit",
                    systemImage: viewModel.isEditingPersonal ? "checkmark" : "pencil",
                    isOn: viewModel.isEditingPersonal,
                    state: viewModel.isWriting ? .inFlight : .ready
                ) {
                    if viewModel.isEditingPersonal {
                        Task { await viewModel.savePersonalDetails() }
                    } else {
                        viewModel.beginEditingPersonal()
                    }
                }
            }
        }
        // The dial codes on demand, and only for the one control that needs them: 251 countries are not worth a
        // request from a reader who came to change their salary (ADR-0009).
        .task(id: viewModel.isEditingPersonal) {
            guard viewModel.isEditingPersonal else { return }
            await viewModel.loadDialCodes()
        }
        .sheet(isPresented: $isChoosingDialCode) {
            HWPickerSheet(
                title: "account.personal.dialSheet.title",
                searchPrompt: "account.personal.dialSheet.search",
                options: Self.dialCodeOptions(viewModel.dialCodes),
                selection: viewModel.personal.country
            ) { code in
                viewModel.chooseDialCode(country: code)
                isChoosingDialCode = false
            } onClose: {
                isChoosingDialCode = false
            }
        }
    }

    /// The 251 countries as picker rows. A mapping, not a calculation.
    ///
    /// The haystack is the design's own — "name + code + dial code" — supplied by the caller because what a row
    /// matches on is decided where the model is known (``HWPickerOption``).
    nonisolated static func dialCodeOptions(_ countries: [Country]) -> [HWPickerOption] {
        countries.map { country in
            HWPickerOption(
                id: country.code,
                name: country.name,
                leading: .code(country.code),
                meta: country.dialCode,
                searchText: "\(country.name) \(country.code) \(country.dialCode)"
            )
        }
    }
}

/// Everything on the Personal Information page the reader looks at — the four lines, the verification banner, and
/// the save button.
///
/// **Separate from ``AccountPersonalPage`` because `ImageRenderer` does not lay out the content of a `ScrollView`**
/// — see the note on that page's `body`. It holds no scroll view, no toolbar and no sheet, so a test can photograph
/// it; what it takes is the view model and one closure, because the sheet it opens belongs to the page around it.
struct AccountPersonalCard: View {
    /// The app's locale, for the one string on this card that is not drawn by a `Text` — see the phone line.
    @Environment(\.locale) private var locale

    let viewModel: AccountViewModel
    /// Opens the country sheet, which the page owns because a sheet is presentation state of the page rather than
    /// of the card.
    let onChangeDialCode: () -> Void

    var body: some View {
        if let details = viewModel.personalDetails {
            content(details)
        } else {
            AccountDetailUnavailable()
        }
    }

    /// "Not given", in the language the user chose. See the phone line for why this is not a bare
    /// `String(localized:)`.
    nonisolated static func notGiven(in locale: Locale) -> String {
        var resource = LocalizedStringResource("account.personal.phone.none")
        resource.locale = locale
        return String(localized: resource)
    }

    @ViewBuilder
    private func content(_ details: AccountScreen.Personal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HWRowCard(caption: "account.personal.card") {
                HWInfoRow("account.personal.username", isSeparated: false) {
                    if viewModel.isEditingPersonal {
                        HWInlineField(
                            "account.personal.username",
                            text: Binding(
                                get: { viewModel.personal.displayName },
                                set: { viewModel.editDisplayName($0) }
                            ),
                            textContentType: .name,
                            isInvalid: viewModel.personal.failures.contains(.nameMissing)
                        )
                    } else {
                        HWInfoValue(details.displayName)
                    }
                }
                if viewModel.personal.failures.contains(.nameMissing) {
                    HWFieldNote("account.personal.error.name")
                }

                HWInfoRow("account.personal.salary") {
                    if viewModel.isEditingPersonal {
                        HWInlineField(
                            "account.personal.salary",
                            text: Binding(get: { viewModel.personal.salary }, set: { viewModel.editSalary($0) }),
                            symbol: viewModel.salarySymbol,
                            keyboardType: .decimalPad,
                            isInvalid: viewModel.personal.failures.contains(.salaryMissing)
                        )
                    } else {
                        // **The server's display string, and the only thing the client renders for a monetary
                        // value** (ADR-0003). What the field above is filled from is `Money.minor`, which has
                        // never been through a formatter — that pair is defect D16's fix.
                        HWInfoValue(details.salary.display, unit: "account.personal.salary.unit")
                    }
                }
                if viewModel.personal.failures.contains(.salaryMissing) {
                    HWFieldNote("account.personal.error.salary")
                }

                HWInfoRow("account.personal.email") {
                    HWInfoValue(details.email, isLocked: true)
                }
                HWInfoNote("account.personal.email.note")

                HWInfoRow("account.personal.phone") {
                    if viewModel.isEditingPersonal {
                        phoneEditor
                    } else {
                        // **The fallback resolves in the app's locale, not the device's.** `String(localized:)`
                        // resolves against the *resource's* locale, which is the device's unless it is told
                        // otherwise — so under Arabic this one line came back in English while every `Text` around
                        // it mirrored. The same correction `HWAnnouncement.text(_:in:)` records (ADR-0011,
                        // ADR-0024), and `hwLanguage(_:)` is what put the right locale in the environment.
                        HWInfoValue(details.phone?.display ?? Self.notGiven(in: locale))
                    }
                }
                if viewModel.personal.failures.contains(.phoneInvalid) {
                    HWFieldNote("account.personal.error.phone")
                }
            }

            // **Beside the email it is about, not above the tabs.** The shell already carries the app-wide
            // reminder (ADR-0031); this one sits next to the address and the sentence explaining that the address
            // cannot be changed, which is where a reader would look for it.
            if !details.isEmailVerified {
                HWBanner("account.personal.email.unverified", systemImage: "envelope.badge")
            }

            if viewModel.isEditingPersonal {
                // The design's `#save-pi`, which appears only in edit mode. The `.editbtn` in the bar commits too
                // — the design wires both to `savePersonal` — and both go through the one method, so there is no
                // second code path to keep in step.
                HWButton(
                    "account.personal.save",
                    systemImage: "checkmark",
                    state: viewModel.isWriting ? .inFlight : .ready
                ) {
                    Task { await viewModel.savePersonalDetails() }
                }
            }
        }
    }

    /// `.phone-wrap` — the dial trigger and the national digits, side by side.
    private var phoneEditor: some View {
        HStack(spacing: 8) {
            HWDialTrigger(
                countryCode: viewModel.personal.country,
                dialCode: viewModel.personal.dialCode,
                label: "account.personal.phone.dial",
                action: onChangeDialCode
            )

            HWInlineField(
                "account.personal.phone",
                text: Binding(get: { viewModel.personal.national }, set: { viewModel.editPhoneDigits($0) }),
                keyboardType: .phonePad,
                textContentType: .telephoneNumber,
                isInvalid: viewModel.personal.failures.contains(.phoneInvalid)
            )
        }
    }

}

/// The refusal beside a control that could not do what it was asked, or **nothing at all**.
///
/// Three callers — the two option pages and the export button — so it is a view rather than three copies of
/// `HWBanner(copy(for:), systemImage: glyph(for:), tone: .refusal)`. That duplication is exactly what
/// `Components.swift`'s rule is about, and review found it one layer above the components.
///
/// `nil` draws nothing, which is what keeps the three call sites to one line each.
struct AccountRefusalNote: View {
    let reason: AccountViewModel.Refusal.Reason?

    var body: some View {
        if let reason {
            HWBanner(
                AccountView.copy(for: reason),
                systemImage: Self.glyph(for: reason),
                tone: .refusal
            )
            .padding(.bottom, 14)
        }
    }

    /// The glyph beside a refusal, as a **named function** rather than a ternary at the call site.
    ///
    /// The reason is the localisation scan, and it is the same reason `HWRunHeader.heart` is a function: the scan
    /// strips a `systemImage:` argument before reading catalogue keys out of a line, and it can read a ternary
    /// whose condition is an identifier but not one whose condition is a *comparison*. So
    /// `refusal == .needsConnection ? "wifi.slash" : …` left two SF Symbol names reading as keys with nothing
    /// behind them. A function is subtracted from the scan's set instead — `LocalisationTests` asks this type for
    /// its glyphs rather than guessing from the text, so a changed glyph does not silently stop being subtracted.
    nonisolated static func glyph(for reason: AccountViewModel.Refusal.Reason) -> String {
        switch reason {
        // Not reachable, and not broken — the same distinction `StateView` draws between offline and failed.
        case .needsConnection: "wifi.slash"
        case .refused: "exclamationmark.triangle"
        }
    }
}

/// The design's `.err` under a row — a field's message, in the card rather than in a toast.
///
/// The design toasts "Check the highlighted details." and reddens the rows. The toast is dropped and the message
/// is put under the box it is about, for the reason `HWTextField` keeps its own message in the accessibility tree:
/// a toast is transient, is announced once, and is unreachable to somebody who has "Speak Hints" off — and the
/// user has to be able to read *which* rule they broke while they fix it.
struct HWFieldNote: View {
    @Environment(ThemeManager.self) private var theme

    private let message: LocalizedStringResource

    init(_ message: LocalizedStringResource) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.hw(.micro))
            .foregroundStyle(theme.palette.feedback.danger)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
    }
}

// MARK: - Language

/// The language page — **the two shipped languages, and nothing else** (Product Spec §3.7 **[FIX]**, ADR-0011).
///
/// The design lists 87 and this lists two. That is the [FIX] rather than a shortcut: the other 85 are reference
/// content the backend serves, and offering a language with no copy behind it is a promise the app cannot keep.
/// Nothing in this file fetches a language list at all — the source is `AppLanguage.shipped`.
///
/// Each row is the language's **endonym**, resolved in its own locale (``AppLanguage/endonym``): a picker that
/// named Arabic "Arabic" to an English reader and "الإنجليزية" to an Arabic one is a picker in which neither
/// reader can find their own language.
struct AccountLanguagePage: View {
    let viewModel: AccountViewModel

    /// Set by the row that was tapped, so the page can close itself once the switch has landed — as the design's
    /// option page does (`setTimeout(() => { close(); say(...) })`).
    @Environment(\.dismiss) private var dismiss

    /// **No `ScrollView` of its own**, and that is not an omission: ``HWOptionList`` scrolls its rows and keeps the
    /// blurb and the search box still above them. Wrapping it would nest one scroll view inside another, which
    /// SwiftUI resolves by giving the inner one its *ideal* height — 160 currencies came back as a ten-thousand-point
    /// page, which is how photographing it found this.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccountRefusalNote(reason: viewModel.refusal(about: .language))

            HWOptionList(
                blurb: "account.language.blurb",
                searchPrompt: "account.language.search",
                options: Self.options(viewModel.shippedLanguages),
                // **The payload's language, not the manager's.** The manager is optimistic and reverts on
                // failure (ADR-0024), so following it would tick a language the server has not accepted.
                selection: viewModel.storedLanguage?.rawValue
            ) { tag in
                guard let selected = AppLanguage(rawValue: tag) else { return }
                Task {
                    await viewModel.selectLanguage(selected)
                    if viewModel.refusal(about: .language) == nil { dismiss() }
                }
            }
            .disabled(viewModel.isWriting)
        }
        .padding(.vertical, 14)
        .navigationTitle(Text("account.language.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The shipped languages as picker rows — the endonym as the name, the tag as the chip.
    nonisolated static func options(_ languages: [AppLanguage]) -> [HWPickerOption] {
        languages.map { language in
            HWPickerOption(
                id: language.rawValue,
                name: language.endonym,
                leading: .code(language.rawValue.uppercased()),
                searchText: "\(language.endonym) \(language.rawValue)"
            )
        }
    }
}

// MARK: - Currency

/// The currency page — 160 of them, from the cacheable reference list (ADR-0009).
///
/// **Online-only by design** (ADR-0003, ADR-0038): every figure the app shows was converted server-side at read,
/// so a change the server has not accepted would be one currency's label over another's arithmetic. Offline, the
/// list is disabled and the explanation is above it — the tick stays where the server left it and nothing on any
/// screen moves.
struct AccountCurrencyPage: View {
    let viewModel: AccountViewModel

    @Environment(\.dismiss) private var dismiss

    /// No `ScrollView` of its own, for the reason ``AccountLanguagePage`` records: the list scrolls and the blurb
    /// and search box stay put above it.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccountRefusalNote(reason: viewModel.refusal(about: .currency))

            HWOptionList(
                blurb: "account.currency.blurb",
                searchPrompt: "account.currency.search",
                options: Self.options(viewModel.displayCurrencies),
                selection: viewModel.displayCurrency?.rawValue
            ) { code in
                Task {
                    await viewModel.selectCurrency(code)
                    if viewModel.refusal(about: .currency) == nil { dismiss() }
                }
            }
            // **Disabled while a change is in flight, and not after one that failed.** It read
            // `|| refusal != nil` until review, which is the criterion's word "disabled" taken too literally: with
            // nothing clearing the refusal, one attempt with no connection left the picker dead for the rest of the
            // session and the user unable to try the change they had just been told had not happened. The
            // explanation is what says nothing changed; a control that cannot be tried again is worse than the
            // failure it reports (ADR-0038).
            .disabled(viewModel.isWriting)
        }
        .padding(.vertical, 14)
        .navigationTitle(Text("account.currency.title"))
        .navigationBarTitleDisplayMode(.inline)
        // The 160 currencies on demand, for the reason the dial codes are: a screen paints from one request
        // (ADR-0020) and a list nobody may ask for is not worth a second one at load time.
        .task { await viewModel.loadCurrencies() }
    }

    /// The 160 currencies as picker rows — the symbol as the chip, the ISO code as the meta, both searchable.
    ///
    /// The design's own haystack: "name + code + symbol".
    nonisolated static func options(_ currencies: [Currency]) -> [HWPickerOption] {
        currencies.map { currency in
            HWPickerOption(
                id: currency.code,
                name: currency.name,
                leading: .symbol(currency.symbol),
                meta: currency.code,
                searchText: "\(currency.name) \(currency.code) \(currency.symbol)"
            )
        }
    }
}

// MARK: - Password

/// The design's password wizard — current password, **both** security questions, then the new one.
///
/// **Three steps and one request** (``PasswordChange``). The steps are this screen's sequencing; nothing exists
/// server-side until the last button, and the refusal names which step was wrong. That is registration's decision
/// applied again (ADR-0031), and there is a second reason here: a route that answered "is this the right current
/// password?" before being told the new one would be a password-checking oracle behind a session.
///
/// **The answers are not checked here** (invariant 5, defect D4). The design reduces both the typed and the stored
/// answer to key words and compares them with a Levenshtein distance in the browser; §4.3 **[FIX]** normalises and
/// compares argon2id hashes server-side, so what this screen does with an answer is send it.
struct AccountPasswordPage: View {
    // No theme: every colour on this page belongs to a component — see the note on ``AccountPersonalPage``.
    let viewModel: AccountViewModel

    @Environment(\.dismiss) private var dismiss

    /// **The chrome, and the flow is ``AccountPasswordSteps``** — the ADR-0033 split, for the reason
    /// ``AccountPersonalPage`` records.
    var body: some View {
        ScrollView {
            AccountPasswordSteps(viewModel: viewModel, onFinished: { dismiss() })
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(Text("account.password.title"))
        .navigationBarTitleDisplayMode(.inline)
        // Starts the flow at step one with an empty answer per question, and — because a page that is left holds
        // two passwords in memory — clears it again on the way out.
        .task { viewModel.beginPasswordChange() }
        .onDisappear { viewModel.beginPasswordChange() }
    }
}

/// The password flow itself: the step bar, the card the step is drawn in, and the button that moves it on.
///
/// **Separate from ``AccountPasswordPage`` because `ImageRenderer` does not lay out the content of a `ScrollView`**
/// — see the note on that page's `body`.
struct AccountPasswordSteps: View {
    @Environment(ThemeManager.self) private var theme

    let viewModel: AccountViewModel
    /// Closes the page once the change has landed, as the design's own flow does (`close(); say(...)`). The
    /// dismissal belongs to the page, so what this holds is the intent.
    let onFinished: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                HWStepBar(
                    stepCount: AccountViewModel.PasswordStep.allCases.count,
                    currentIndex: viewModel.password.step.rawValue,
                    label: Self.stepLabel(viewModel.password.step),
                    backLabel: "account.password.back",
                    appearance: .surface,
                    // `nil` on the first step, where the design hides `.stepback`: the way out of the flow is the
                    // stack's own back button.
                    onBack: viewModel.password.step == .currentPassword
                        ? nil
                        : { viewModel.retreatPasswordChange() }
                )

                HWCard { step }

                HWButton(
                    Self.actionTitle(viewModel.password.step),
                    systemImage: viewModel.password.step == .newPassword ? "checkmark" : nil,
                    state: viewModel.isWriting ? .inFlight : .ready
                ) {
                    Task {
                        await viewModel.advancePasswordChange()
                        if viewModel.notice == .passwordChanged { onFinished() }
                    }
                }
        }
    }

    @ViewBuilder
    private var step: some View {
        switch viewModel.password.step {
        case .currentPassword: currentPasswordStep
        case .securityQuestions: questionsStep
        case .newPassword: newPasswordStep
        }
    }

    /// Step one — `.step-h`, `.step-p`, and the box.
    private var currentPasswordStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("account.password.current.heading", "account.password.current.blurb")

            HWTextField(
                "account.password.current.field",
                text: Binding(get: { viewModel.password.current }, set: { viewModel.editCurrentPassword($0) }),
                systemImage: "lock",
                textContentType: .password,
                error: Self.message(for: viewModel.password.failure, on: .currentPassword),
                isSecure: true
            )
        }
    }

    /// Step two — the account's **two** questions, from the payload.
    private var questionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("account.password.questions.heading", "account.password.questions.blurb")

            ForEach(Array(viewModel.securityQuestions.enumerated()), id: \.element.id) { index, question in
                VStack(alignment: .leading, spacing: 7) {
                    // **The question is a line of its own and the field's label is "Your answer"** — the shape
                    // registration already has, and for the same reason: a question is *server content* in the
                    // reader's language (§4.3 **[FIX]**), and `HWTextField`'s label is a catalogue key because a
                    // field's name is never a server string. Passing the question text as a key would look up a
                    // sentence and find nothing behind it.
                    Text(verbatim: question.text)
                        .hwLabel()
                        .fixedSize(horizontal: false, vertical: true)

                    HWTextField(
                        "account.password.questions.answer",
                        text: Binding(
                            get: { viewModel.password.answers.indices.contains(index)
                                ? viewModel.password.answers[index]
                                : ""
                            },
                            set: { viewModel.editAnswer(at: index, $0) }
                        ),
                        systemImage: "checkmark.shield",
                        // **The message goes under the first box only.** The server does not say which answer
                        // missed and must not (`ErrorCode.securityAnswersInvalid`), so repeating it under both
                        // would read as two separate refusals of two separate answers.
                        error: index == 0
                            ? Self.message(for: viewModel.password.failure, on: .securityQuestions)
                            : nil
                    )
                }
            }

            // The design points at support after three misses, which is the only thing left that helps somebody
            // who cannot answer their own questions. It says nothing about *which* answer was wrong, because the
            // server does not say (`ErrorCode.securityAnswersInvalid`).
            if viewModel.password.shouldOfferSupport {
                HWInfoNote("account.password.questions.support")
            }
        }
    }

    /// Step three — the new password, the strength meter, and the confirmation.
    private var newPasswordStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("account.password.new.heading", "account.password.new.blurb")

            VStack(alignment: .leading, spacing: 9) {
                HWTextField(
                    "account.password.new.field",
                    text: Binding(get: { viewModel.password.newPassword }, set: { viewModel.editNewPassword($0) }),
                    systemImage: "lock",
                    textContentType: .newPassword,
                    error: Self.message(for: viewModel.password.failure, on: .newPassword),
                    isSecure: true
                )

                // Feedback, and it gates nothing: the only rule that refuses a password is 8+ (invariant 4).
                HWStrengthMeter(
                    filled: viewModel.passwordStrength.rawValue,
                    outOf: PasswordStrength.strong.rawValue,
                    label: Self.strengthLabel(viewModel.passwordStrength),
                    appearance: .surface
                )
            }

            HWTextField(
                "account.password.new.confirm",
                text: Binding(get: { viewModel.password.confirmation }, set: { viewModel.editConfirmation($0) }),
                systemImage: "checkmark.shield",
                textContentType: .newPassword,
                error: viewModel.password.failure == .confirmationMismatch
                    ? "account.password.error.mismatch"
                    : nil,
                isSecure: true
            )
        }
    }

    /// `.step-h` over `.step-p`.
    private func heading(_ title: LocalizedStringResource, _ blurb: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.hw(.subheading))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(blurb)
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The two lines are one heading, read together — and it *is* a heading: it is the first thing on the step.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Mapping

    /// `.steplab` — "Step 2 of 3", as copy rather than two numbers joined (ADR-0011).
    nonisolated static func stepLabel(_ step: AccountViewModel.PasswordStep) -> LocalizedStringResource {
        switch step {
        case .currentPassword: "account.password.step.one"
        case .securityQuestions: "account.password.step.two"
        case .newPassword: "account.password.step.three"
        }
    }

    /// What the button says, which is the design's own three words: Continue · Check my answers · Update password.
    nonisolated static func actionTitle(_ step: AccountViewModel.PasswordStep) -> LocalizedStringResource {
        switch step {
        case .currentPassword: "account.password.continue"
        case .securityQuestions: "account.password.check"
        case .newPassword: "account.password.submit"
        }
    }

    /// One failure as the message under the box it is about, or `nil` on a step it is not about.
    ///
    /// Filtered by step rather than shown wherever the flow happens to be: a server refusal sends the reader back
    /// to the step it names (``AccountViewModel/PasswordDraft/Failure/step``), and a message drawn on the wrong
    /// step would be a sentence about a box that is not on screen.
    nonisolated static func message(
        for failure: AccountViewModel.PasswordDraft.Failure?,
        on step: AccountViewModel.PasswordStep
    ) -> LocalizedStringResource? {
        guard let failure, failure.step == step else { return nil }
        return switch failure {
        case .currentPasswordMissing: "account.password.error.currentMissing"
        case .answerMissing: "account.password.error.answerMissing"
        case .newPasswordTooShort: "account.password.error.tooShort"
        case .confirmationMismatch: "account.password.error.mismatch"
        case .currentPasswordRejected: "account.password.error.currentRejected"
        case .answersRejected: "account.password.error.answersRejected"
        }
    }

    /// The strength meter's word. `nil` while there is nothing to measure, which is what draws the bars alone.
    ///
    /// The same four words registration's meter uses, from the same catalogue keys: two copies of "Weak" would be
    /// two strings to translate and one to get wrong.
    nonisolated static func strengthLabel(_ strength: PasswordStrength) -> LocalizedStringResource? {
        switch strength {
        case .none: nil
        case .weak: "registration.password.strength.weak"
        case .fair: "registration.password.strength.fair"
        case .good: "registration.password.strength.good"
        case .strong: "registration.password.strength.strong"
        }
    }
}

#if DEBUG
/// A pushed page over a view model that has been **loaded first**.
///
/// The four pages are not `BaseView` conformances and so have no `.task` of their own (see the note at the top of
/// this file) — they draw whatever the screen behind them already fetched. A preview therefore has to do the
/// fetching, which is what this wrapper is for: the real view model, over the real fixture transport, through the
/// real `load()` (ADR-0013).
private struct AccountPagePreview<Page: View>: View {
    let viewModel: AccountViewModel
    @ViewBuilder let page: () -> Page

    var body: some View {
        NavigationStack { page() }
            .task { try? await viewModel.load() }
    }
}

#Preview("Personal information — at rest") {
    let viewModel = AccountViewModel.previewINR
    AccountPagePreview(viewModel: viewModel) { AccountPersonalPage(viewModel: viewModel) }.hwTheme()
}

#Preview("Personal information — unverified, no phone number") {
    let viewModel = AccountViewModel.previewUnverified
    AccountPagePreview(viewModel: viewModel) { AccountPersonalPage(viewModel: viewModel) }.hwTheme()
}

#Preview("Language — two, not eighty-seven") {
    let viewModel = AccountViewModel.previewINR
    AccountPagePreview(viewModel: viewModel) { AccountLanguagePage(viewModel: viewModel) }.hwTheme()
}

#Preview("Currency — one hundred and sixty") {
    let viewModel = AccountViewModel.previewINR
    AccountPagePreview(viewModel: viewModel) { AccountCurrencyPage(viewModel: viewModel) }.hwTheme()
}

#Preview("Password — the first step") {
    let viewModel = AccountViewModel.previewINR
    AccountPagePreview(viewModel: viewModel) { AccountPasswordPage(viewModel: viewModel) }.hwTheme()
}

#Preview("Personal information — Arabic, right to left") {
    let viewModel = AccountViewModel.previewINR
    AccountPagePreview(viewModel: viewModel) { AccountPersonalPage(viewModel: viewModel) }
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("Personal information — AX5") {
    let viewModel = AccountViewModel.previewINR
    AccountPagePreview(viewModel: viewModel) { AccountPersonalPage(viewModel: viewModel) }
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
