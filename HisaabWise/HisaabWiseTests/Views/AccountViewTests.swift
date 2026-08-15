import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// Account's screen: what it maps, what it refuses to work out, what it draws, and the copy behind every key it
/// renders.
///
/// A whole-screen render is a smoke test here for the reason `CONTEXT.md` records: `ScreenChrome` supplies
/// `.task { load() }`, `load()` writes `.loading` first, and `ImageRenderer` yields to the main actor before it
/// captures — so the pixels are the spinner however loaded the view model was. The claims worth asserting are the
/// **mappings**, which are `static`, `nonisolated`, and total, plus the copy — and the page and the four detail
/// pages, which can be photographed because none of them has a task of its own.
@Suite("AccountView")
@MainActor
struct AccountViewTests {
    private static func loaded(_ fixture: Fixture = .accountINR) async throws -> (AccountViewModel, AccountScreen) {
        let client = TestBench.client(
            FixtureTransport(stubs: [
                Endpoint.screenAccount: try .ok(fixture),
                Endpoint.path(for: .currencies): try .ok(.referenceCurrencies),
                Endpoint.path(for: .countries): try .ok(.referenceCountries),
            ])
        )
        let viewModel = AccountViewModel(
            client: client,
            content: ContentLoader(client: client, store: InMemoryContentStore()),
            language: LanguageManager(selected: .english),
            session: SessionCoordinator(
                client: client,
                keptStore: InMemoryTokenStore(),
                transientStore: InMemoryTokenStore()
            )
        )
        try await viewModel.load()
        return (viewModel, try #require(viewModel.state.value))
    }

    /// A session object for the environment, because the account page carries ``LogoutControl`` and that control
    /// reads the session rather than taking a closure — what "log out" means is not a decision a screen gets to
    /// make differently (`AppShellTests` keeps `signOut()` to one caller).
    ///
    /// Not signed in, and it does not need to be: nothing here presses the control. What would happen without one
    /// is a **trap** rather than an empty render — an `@Environment` of a non-optional observable object is
    /// resolved when the view updates (`CONTEXT.md`), which is how this suite found the coupling.
    private static func session() -> SessionCoordinator {
        SessionCoordinator(
            client: TestBench.client(FixtureTransport()),
            keptStore: InMemoryTokenStore(),
            transientStore: InMemoryTokenStore()
        )
    }

    // MARK: - The mapping into the design system

    /// Four sections, four glyphs, **one each** — two rows drawn with the same icon is a settings list a reader
    /// cannot scan.
    @Test("every section has a glyph of its own, and none encodes a direction")
    func theGlyphsAreDistinctAndDirectionless() {
        let glyphs = AccountScreen.Section.allCases.map(AccountView.glyph)

        #expect(glyphs.count == 4)
        #expect(Set(glyphs).count == 4)
        for glyph in glyphs {
            // The rule `LocalisationTests` applies app-wide, checked here against the values: a glyph chosen from
            // a list of four is exactly where a `.left`/`.right` symbol slips in, and the row mirrors while the
            // icon would not (ADR-0011).
            #expect(!glyph.contains("left"), "\(glyph) points left in every language")
            #expect(!glyph.contains("right"), "\(glyph) points right in every language")
        }
    }

    /// The two refusal glyphs are distinct, and the offline one is the calm informational symbol rather than a
    /// warning — the distinction ADR-0016 draws between offline and failed, applied to a notice.
    @Test("the two refusal reasons are drawn differently")
    func theRefusalsAreDistinct() {
        let glyphs = AccountViewModel.Refusal.Reason.allCases.map(AccountRefusalNote.glyph)

        #expect(Set(glyphs).count == 2)
        #expect(AccountRefusalNote.glyph(for: .needsConnection) == "wifi.slash")
    }

    /// **The password row's value is the app's mask, and every other row's is the payload's.** The server has no
    /// password to send and must never send a stand-in for one.
    @Test("only the password row draws a value the payload did not send")
    func onlyThePasswordRowIsMasked() async throws {
        let (_, screen) = try await Self.loaded()

        for row in screen.rows {
            let value = AccountView.value(for: row)
            if row.section == .password {
                #expect(value == Text("account.row.passwordMask"))
                #expect(row.value == nil, "the payload sent a password stand-in")
            } else {
                #expect(value == row.value.map { Text(verbatim: $0) }, "\(row.section)")
            }
        }
    }

    /// Every notice has words, and each is its own sentence: four writes that all toasted the same thing would
    /// tell the user nothing about which one landed.
    @Test("every notice maps to copy of its own")
    func everyNoticeHasItsOwnCopy() throws {
        let copy = AccountViewModel.Notice.allCases.map(AccountView.copy)

        #expect(copy.count == 4)
        #expect(copy.allSatisfy { $0 != nil })
        #expect(Set(copy.compactMap { $0?.key }).count == 4)
        // And no notice means no toast, which is what dismissing one leaves behind.
        #expect(AccountView.copy(for: nil) == nil)
    }

    @Test("every refusal reason maps to copy of its own")
    func everyRefusalHasItsOwnCopy() {
        let copy = AccountViewModel.Refusal.Reason.allCases.map(AccountView.copy)

        #expect(Set(copy.map(\.key)).count == 2)
    }

    /// `nil` draws nothing, which is what lets the three call sites be one line each.
    ///
    /// Measured inside a container, because a view with no content has no size at all and `ImageRenderer` answers
    /// with `nil` rather than an empty picture — the assertion is that the note adds nothing to what is around it.
    @Test("the refusal note draws nothing when there is nothing to say")
    func theRefusalNoteIsEmptyWhenThereIsNoRefusal() throws {
        func measure(_ reason: AccountViewModel.Refusal.Reason?) -> CGSize? {
            TestBench.measure(
                VStack(spacing: 0) {
                    Text(verbatim: "anchor")
                    AccountRefusalNote(reason: reason)
                }
            )
        }

        let nothing = try #require(measure(nil))
        let something = try #require(measure(.needsConnection))

        #expect(nothing.height < something.height)
    }

    /// **"Not given" is resolved in the app's locale, not the device's.** `String(localized:)` resolves against the
    /// resource's own locale unless it is told otherwise, so this line came back in English under Arabic while every
    /// `Text` around it mirrored — the correction `HWAnnouncement.text(_:in:)` already records (ADR-0011).
    @Test("the phone fallback is resolved in the language the user chose")
    func thePhoneFallbackFollowsTheAppLocale() {
        let english = AccountPersonalCard.notGiven(in: AppLanguage.english.locale)
        let arabic = AccountPersonalCard.notGiven(in: AppLanguage.arabic.locale)

        #expect(!english.isEmpty)
        #expect(english != "account.personal.phone.none", "the key reached the screen")
        // The catalogue is English-only until the Phase 5 translation pass (ADR-0011), so the two agree *today*.
        // What is asserted is that the locale is honoured at all — a bare `String(localized:)` would read the
        // machine's.
        #expect(arabic == String(localized: {
            var resource = LocalizedStringResource("account.personal.phone.none")
            resource.locale = AppLanguage.arabic.locale
            return resource
        }()))
    }

    /// Every step has a label and a button word of its own, and the three buttons are the design's three: Continue
    /// · Check my answers · Update password.
    @Test("every password step has a label and a button word of its own")
    func everyStepIsLabelled() {
        let steps = AccountViewModel.PasswordStep.allCases

        #expect(steps.count == 3)
        #expect(Set(steps.map { AccountPasswordSteps.stepLabel($0).key }).count == 3)
        #expect(Set(steps.map { AccountPasswordSteps.actionTitle($0).key }).count == 3)
    }

    /// **A message is only ever drawn on the step it is about.** A refusal sends the reader back to a step, and a
    /// sentence rendered on the wrong one would be about a box that is not on screen.
    @Test("a failure's message appears on its own step and nowhere else")
    func aFailureAppearsOnOneStepOnly() {
        for failure in AccountViewModel.PasswordDraft.Failure.allCases {
            for step in AccountViewModel.PasswordStep.allCases {
                let message = AccountPasswordSteps.message(for: failure, on: step)
                #expect((message != nil) == (failure.step == step), "\(failure) on \(step)")
            }
        }
        // And the four steps' worth of failures are four distinct sentences per step, not one shared apology.
        let messages = AccountViewModel.PasswordDraft.Failure.allCases
            .compactMap { AccountPasswordSteps.message(for: $0, on: $0.step)?.key }
        #expect(Set(messages).count == AccountViewModel.PasswordDraft.Failure.allCases.count)
    }

    /// The strength meter's words are **registration's own keys**, not a second set: two copies of "Weak" would be
    /// two strings to translate and one to get wrong.
    @Test("the strength meter borrows registration's four words, and says nothing at zero")
    func theStrengthWordsAreShared() {
        #expect(AccountPasswordSteps.strengthLabel(.none) == nil)
        for strength in PasswordStrength.allCases where strength != .none {
            let key = try? #require(AccountPasswordSteps.strengthLabel(strength)?.key)
            #expect(key?.hasPrefix("registration.password.strength.") == true, "\(strength)")
        }
    }

    /// The language rows are the **two shipped languages**, each named in its own tongue — never the design's 87
    /// (Product Spec §3.7 **[FIX]**).
    @Test("the language rows are the offered set, each named in itself")
    func theLanguageRowsAreEndonyms() {
        let options = AccountLanguagePage.options(AppLanguage.shipped)

        #expect(options.map(\.id) == ["en", "ar", "hi"])
        #expect(
            options.map(\.name)
                == [AppLanguage.english.endonym, AppLanguage.arabic.endonym, AppLanguage.hindi.endonym]
        )
        // The whole point of an endonym: an Arabic reader can find Arabic in an English app.
        #expect(AppLanguage.arabic.endonym != "Arabic")
        #expect(options.allSatisfy { !$0.name.isEmpty })
    }

    /// The currency rows carry the design's own haystack — "name + code + symbol" — so a search by ISO code finds
    /// the currency.
    @Test("a currency can be found by its name, its code, or its symbol")
    func theCurrencyRowsAreSearchable() throws {
        let currencies = try Fixture.referenceCurrencies.decode(CurrencyList.self).currencies
        let options = AccountCurrencyPage.options(currencies)

        #expect(options.count == 160)
        for needle in ["dirham", "AED", "د.إ"] {
            #expect(HWOptionList.filtered(options, matching: needle).contains { $0.id == "AED" }, "\(needle)")
        }
        // And 160 rows clear the twelve-row threshold, so the page gets a search box at all.
        #expect(options.count > HWOptionList.searchThreshold)
    }

    /// **A currency symbol is text, not an SF Symbol name.** `HWSheetRowLeading` has a case called `symbol` that
    /// carries a *glyph name* and draws `Image(systemName:)`, so passing `₹` to it drew nothing at all and 160 rows
    /// came up chipless — which only looking at the running app found. The chip is a code chip, as registration's own
    /// currency sheet passes.
    @Test("every currency row's chip is its symbol as text")
    func theCurrencyChipIsText() throws {
        let currencies = try Fixture.referenceCurrencies.decode(CurrencyList.self).currencies
        let options = AccountCurrencyPage.options(currencies)

        for option in options {
            let currency = try #require(currencies.first { $0.code == option.id })
            #expect(option.leading == .code(currency.symbol), "\(option.id) draws its symbol as a glyph name")
        }
    }

    /// The dial-code rows carry the design's haystack too — "name + code + dial code".
    @Test("a country can be found by its name, its code, or its dial code")
    func theDialCodeRowsAreSearchable() throws {
        let countries = try Fixture.referenceCountries.decode(CountryList.self).countries
        let options = AccountPersonalPage.dialCodeOptions(countries)

        #expect(options.count == 251)
        for needle in ["emirates", "AE", "+971"] {
            #expect(HWOptionList.filtered(options, matching: needle).contains { $0.id == "AE" }, "\(needle)")
        }
    }

    // MARK: - It renders

    /// **What is photographed is the content, not the page** — the four pages that scroll are photographed through
    /// the views inside their `ScrollView`s, because `ImageRenderer` does not lay a `ScrollView`'s content out and a
    /// render of the page comes back as an empty ground that this assertion would pass on (ADR-0033). Photographing
    /// them is how that was found.
    ///
    /// The two **option** pages are still rendered whole, and what that proves is smaller and is said here: their
    /// rows live in ``HWSheetList``, which scrolls, so the picture holds the blurb and the search box and not the
    /// 160 currencies. The rows are asserted through the mappings above instead.
    @Test("every page's content renders")
    func everyPageRenders() async throws {
        let (viewModel, screen) = try await Self.loaded()
        await viewModel.loadCurrencies()

        #expect(
            TestBench.render(
                AccountPage(screen: screen, viewModel: viewModel).environment(Self.session()),
                height: nil
            ) != nil
        )
        #expect(
            TestBench.render(
                AccountPersonalCard(viewModel: viewModel, onChangeDialCode: {}),
                height: nil
            ) != nil
        )
        #expect(TestBench.render(AccountPasswordSteps(viewModel: viewModel, onFinished: {}), height: nil) != nil)
        #expect(TestBench.render(AccountLanguagePage(viewModel: viewModel)) != nil)
        #expect(TestBench.render(AccountCurrencyPage(viewModel: viewModel)) != nil)
    }

    /// The unverified payload draws two branches the standing one does not: the banner beside the locked email, and
    /// a phone line with no number behind it.
    @Test("the personal page renders with no phone number and an unconfirmed address")
    func theUnverifiedPageRenders() async throws {
        let (viewModel, screen) = try await Self.loaded(.accountUnverified)

        #expect(screen.personal.phone == nil)
        #expect(!screen.personal.isEmailVerified)
        #expect(
            TestBench.render(
                AccountPersonalCard(viewModel: viewModel, onChangeDialCode: {}),
                height: nil
            ) != nil
        )
    }

    /// Edit mode is a different page — three fields where there were three values — so it is photographed too.
    @Test("the personal page renders in edit mode, and with every field refused")
    func theEditablePageRenders() async throws {
        let (viewModel, _) = try await Self.loaded()

        viewModel.beginEditingPersonal()
        let card = AccountPersonalCard(viewModel: viewModel, onChangeDialCode: {})
        #expect(TestBench.render(card, height: nil) != nil)

        viewModel.editDisplayName("")
        viewModel.editSalary("")
        viewModel.editPhoneDigits("1")
        await viewModel.savePersonalDetails()
        #expect(viewModel.personal.failures.count == 3)
        // **The three messages grow the card**, which is what makes the render above about something: a card that
        // drew them and a card that did not would otherwise be the same picture to `!= nil`.
        let refused = try #require(TestBench.measure(AccountPersonalCard(viewModel: viewModel, onChangeDialCode: {})))
        viewModel.cancelEditingPersonal()
        viewModel.beginEditingPersonal()
        let clean = try #require(TestBench.measure(AccountPersonalCard(viewModel: viewModel, onChangeDialCode: {})))
        #expect(refused.height > clean.height)
    }

    /// **Doubled copy must grow the page rather than be cut off** — ADR-0011's pseudolanguage harness, applied to
    /// the screen whose rows are the longest labels in the app.
    @Test("the page grows under doubled copy rather than truncating")
    func doubledCopyGrowsThePage() async throws {
        let (viewModel, screen) = try await Self.loaded()
        let page = AccountPage(screen: screen, viewModel: viewModel).environment(Self.session())

        let single = try #require(TestBench.measure(page))
        let doubled = try #require(TestBench.measure(page.environment(\.dynamicTypeSize, .accessibility5)))

        #expect(doubled.height > single.height, "the page did not grow — its content was truncated")
    }

    /// Right to left, which is a *shipped* language rather than a later pass (ADR-0011).
    @Test("every page renders right to left")
    func everyPageMirrors() async throws {
        let (viewModel, screen) = try await Self.loaded()
        let arabic = LanguageManager(selected: .arabic)

        #expect(
            TestBench.render(
                AccountPage(screen: screen, viewModel: viewModel)
                    .environment(Self.session())
                    .hwLanguage(arabic),
                height: nil
            ) != nil
        )
        #expect(
            TestBench.render(
                AccountPasswordSteps(viewModel: viewModel, onFinished: {}).hwLanguage(arabic),
                height: nil
            ) != nil
        )
    }

    // MARK: - Copy

    @Test("every key the screen and its four pages render has English copy behind it")
    func everyKeyHasCopy() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: AccountView.copyKeys)
    }

    /// The way out is still the way out: Account is where the design puts it, and `AppShellTests` is what keeps
    /// `signOut()` to one caller.
    @Test("the log-out control's copy is present on the screen that carries it")
    func theLogoutCopyIsPresent() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: LogoutControl.copyKeys)
    }
}
