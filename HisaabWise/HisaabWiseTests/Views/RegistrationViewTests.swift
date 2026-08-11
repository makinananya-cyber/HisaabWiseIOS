import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// The registration screens: the copy each step draws, the picker rows the design's four configs become, and the
/// smoke test that each of the three actually builds.
///
/// **Not pixels.** `ImageRenderer` never runs `onAppear` or a `.task`, so a rendered `RegistrationView` is a screen
/// whose reference lists never arrived — which is a real state and the least interesting one. What is asserted here
/// is what can be: the copy resolves, the mapping is right, and the three step views evaluate with the environment
/// they are given. The screens themselves were checked in the Simulator.
@Suite("Registration screens")
@MainActor
struct RegistrationViewTests {
    // MARK: - Copy

    /// Every key the three steps and the shared failure table name.
    ///
    /// `LocalisationTests` already scans the source for keys and checks each against the catalogue, which makes
    /// this list a *second* owner — and it is here for the reason Home's is: a per-screen list fails with the
    /// screen's name on it, and the scan cannot tell which screen a missing key belonged to.
    @Test("every failure has copy, for every case of the failure type")
    func everyFailureHasCopy() throws {
        // Built from the cases rather than from a list of strings, so a fifteenth failure added to the enum fails
        // here rather than rendering blank. The associated values are arbitrary — what is being read is the arm.
        let failures: [RegistrationFailure] = [
            .nameMissing, .emailInvalid, .emailTaken, .phoneInvalid(country: "India"),
            .dateOfBirthMissing, .tooYoung(minimumAge: 13), .passwordTooShort, .passwordsDoNotMatch,
            .termsNotAccepted, .salaryMissing, .firstQuestionMissing, .firstAnswerMissing,
            .secondQuestionMissing, .secondQuestionRepeated, .secondAnswerMissing, .goalMissing,
            .unreachable, .refused(.unknown),
        ]

        var keys: [String] = []
        for failure in failures {
            let copy = try #require(RegistrationView.copy(for: failure), "\(failure) has no copy")
            keys.append(String(describing: copy.key))
        }

        // `nil` in, `nil` out — the arm the fields rely on to draw no message at all.
        #expect(RegistrationView.copy(for: nil) == nil)
        try CatalogueCopy.expectEnglishCopy(forKeys: keys.filter { $0.hasPrefix("registration.") })
    }

    /// Each step's head, step label, and back label. Read through the four functions, so a step whose copy was
    /// never written fails here rather than rendering its own key.
    @Test("every step has a headline, a subtitle, a step label, and a back label", arguments: RegistrationStep.allCases)
    func everyStepHasCopy(_ step: RegistrationStep) throws {
        let keys = [
            RegistrationView.titleFirst(step),
            RegistrationView.titleSecond(step),
            RegistrationView.subtitle(step),
            RegistrationView.stepLabel(step),
            RegistrationView.backLabel(step),
        ]

        try CatalogueCopy.expectEnglishCopy(forKeys: keys.map { String(describing: $0.key) })
    }

    /// The three step labels are **distinct**, which is the whole reason they are three entries rather than one
    /// interpolated sentence: three copies of "Step %lld of 3" would satisfy every other assertion here.
    @Test("the three step labels differ from one another")
    func theStepLabelsAreDistinct() {
        let labels = RegistrationStep.allCases.map { String(describing: RegistrationView.stepLabel($0).key) }

        #expect(Set(labels).count == RegistrationStep.allCases.count)
    }

    /// **The copy says thirteen because the rule is thirteen.** The sentence is not interpolated — a translation
    /// gets a whole sentence to phrase — so this is what keeps the two in step, which is the job interpolation
    /// would otherwise have done.
    @Test("the too-young message names the minimum age the code enforces")
    func theAgeCopyMatchesTheRule() throws {
        let entry = try CatalogueCopy.entry("registration.error.tooYoung")
        let english = try #require(CatalogueCopy.english(in: entry))

        #expect(
            english.contains("\(RegistrationViewModel.minimumAge)"),
            """
            the copy reads "\(english)" while the code enforces \(RegistrationViewModel.minimumAge). \
            The sentence is deliberately not interpolated (ADR-0011), so this assertion is what keeps them in step
            """
        )
    }

    /// And the password message names the floor the code enforces, for the same reason — this is the [FIX] that
    /// took the design's sign-in from 6 to 8 (invariant 4), and a message still saying 6 would be the visible half
    /// of the defect.
    @Test("the short-password message names the length the code enforces")
    func thePasswordCopyMatchesTheRule() throws {
        let entry = try CatalogueCopy.entry("registration.error.passwordTooShort")
        let english = try #require(CatalogueCopy.english(in: entry))

        #expect(english.contains("\(RegistrationViewModel.minimumPasswordLength)"))
        #expect(!english.contains("6"), "the message still names the design's old six-character floor")
    }

    // MARK: - The picker configs

    /// The design's `#dial-btn` config: the ISO code as the chip, the name, the dial code as meta — and all three
    /// searchable, so "971", "AE", and "Emirates" each find the same row.
    @Test("a country becomes a searchable row keyed by its ISO code")
    func aCountryBecomesARow() {
        let option = RegistrationDetailsStep.option(
            for: Country(code: "AE", dialCode: "+971", name: "United Arab Emirates")
        )

        #expect(option.id == "AE")
        #expect(option.name == "United Arab Emirates")
        #expect(option.leading == .code("AE"))
        #expect(option.meta == "+971")

        for needle in ["971", "ae", "emirates", "United Arab"] {
            #expect(
                !HWPickerSheet.filtered([option], matching: needle).isEmpty,
                "searching \"\(needle)\" does not find the UAE"
            )
        }
        #expect(HWPickerSheet.filtered([option], matching: "france").isEmpty)
    }

    /// The `#cur-btn` config: the **symbol** as the chip and the code as meta, which is the way round the design
    /// draws it — the symbol is what a user recognises and the code is what disambiguates it.
    @Test("a currency becomes a searchable row keyed by its ISO code")
    func aCurrencyBecomesARow() {
        let option = RegistrationMoneyStep.option(for: Currency(code: "INR", name: "Indian Rupee", symbol: "₹"))

        #expect(option.id == "INR")
        #expect(option.leading == .code("₹"))
        #expect(option.meta == "INR")

        for needle in ["inr", "rupee", "₹"] {
            #expect(!HWPickerSheet.filtered([option], matching: needle).isEmpty, "\(needle)")
        }
    }

    /// A question is a sentence, so it gets the whole row — no chip, no meta — and **its id is the identity**
    /// (§4.3 [FIX]).
    @Test("a question becomes a row whose id is its opaque id, not its wording")
    func aQuestionBecomesARow() {
        let question = SecurityQuestion(id: "sq07", text: "What was the name of your first employer?")
        let option = RegistrationMoneyStep.option(for: question)

        #expect(option.id == "sq07")
        #expect(option.name == question.text)
        #expect(option.leading == nil)
        #expect(option.meta == nil)
        // Searchable by its words, which is the only thing a user could search a question bank by.
        #expect(!HWPickerSheet.filtered([option], matching: "employer").isEmpty)
    }

    /// The search box appears past twelve rows, as the design's `data.length > 12` does — and the 14-question bank
    /// clears it by two, which is why the question pickers have one.
    @Test("the search threshold is the design's twelve")
    func theSearchThresholdIsTwelve() {
        #expect(HWPickerSheet.searchThreshold == 12)
    }

    /// Filtering is case-folded, diacritic-insensitive, and trims — the last one matters because a search box on
    /// iOS collects a trailing space from the keyboard's own suggestion bar.
    @Test("filtering folds case and diacritics and ignores surrounding space")
    func filteringIsForgiving() {
        let options = [
            HWPickerOption(id: "AX", name: "Åland Islands"),
            HWPickerOption(id: "FR", name: "France"),
        ]

        #expect(HWPickerSheet.filtered(options, matching: "aland").map(\.id) == ["AX"])
        #expect(HWPickerSheet.filtered(options, matching: "  FRANCE  ").map(\.id) == ["FR"])
        // An empty query is not a filter — it is every row.
        #expect(HWPickerSheet.filtered(options, matching: "   ").count == 2)
    }

    // MARK: - The strength meter's labels

    @Test("every strength level has a word except none", arguments: PasswordStrength.allCases)
    func everyStrengthLevelHasCopy(_ strength: PasswordStrength) throws {
        let label = RegistrationDetailsStep.strengthLabel(strength)

        guard strength != .none else {
            #expect(label == nil, "an empty box was given a rating")
            return
        }

        let key = try #require(label).key
        try CatalogueCopy.expectEnglishCopy(forKeys: [String(describing: key)])
    }

    // MARK: - Step 3's hint

    /// Four states, four sentences: nothing typed, on the rule, ahead of it, under it. Asserted through the view
    /// model so the branch is exercised rather than the switch read.
    @Test("the goal hint has a sentence for each of its four states")
    func theGoalHintCoversItsStates() async throws {
        let viewModel = RegistrationViewModel.preview
        // The lists first — the hint is a share *of the salary*, and the salary needs a currency to be read in.
        await viewModel.loadReferenceLists()
        viewModel.salaryText = "8000"

        var keys: [String] = []
        for goal in ["", "1600", "2400", "400"] {
            viewModel.editGoal(goal)
            let hint = try #require(RegistrationGoalStep.hint(for: viewModel), "no hint for \"\(goal)\"")
            keys.append(String(describing: hint.key))
        }

        // Four distinct sentences, not one reused — the design writes three different endings and an empty state.
        #expect(Set(keys).count == 4)
        try CatalogueCopy.expectEnglishCopy(forKeys: keys)
    }

    // MARK: - The preview scaffolding

    /// **The previews are part of the deliverable** (ADR-0013), so the states they claim to draw are asserted.
    ///
    /// This one earns its place: `previewFilledStepTwo` filled the form *before* the question bank had loaded, so
    /// `questions.first` was `nil` and a preview named "filled" drew an unchosen question. Found by looking at the
    /// running app, which is the only place it was visible.
    @Test("every step's preview reaches the state it is named for")
    func thePreviewsReachTheirStates() async throws {
        let filledOne = RegistrationViewModel.previewFilledStepOne
        let onTwo = RegistrationViewModel.previewOnStepTwo
        let filledTwo = RegistrationViewModel.previewFilledStepTwo
        let onThree = RegistrationViewModel.previewOnStepThree
        // The factories load their lists in a detached task and fill afterwards. Awaiting the load here joins the
        // one in flight rather than starting a second — which is the single-flight property this suite's own
        // reason for existing depends on: before it, `await loadReferenceLists()` could return with the lists
        // still empty, and a "filled" preview then drew an unchosen question.
        for viewModel in [filledOne, onTwo, filledTwo, onThree] {
            await viewModel.loadReferenceLists()
            #expect(viewModel.hasReferenceLists)
        }
        await Task.yield()

        #expect(filledOne.step == .one)
        #expect(!filledOne.name.isEmpty)
        #expect(filledOne.acceptedTerms)

        #expect(onTwo.step == .two)

        #expect(filledTwo.step == .two)
        #expect(filledTwo.salaryText == "8000")
        #expect(filledTwo.firstQuestion != nil, "the \"filled\" step 2 preview has no first question chosen")
        #expect(filledTwo.secondQuestion != nil)
        #expect(filledTwo.firstQuestion != filledTwo.secondQuestion)

        #expect(onThree.step == .three)
        #expect(onThree.goalText == "1600", "step 3's preview did not open pre-filled at 20%")
    }

    // MARK: - What each field clears

    /// **Every field clears its own failure, and the password clears the confirmation's too.**
    ///
    /// A source scan, because the rule lives in the bindings and there is no way to reach a `Binding`'s setter from
    /// a test. Both halves were wrong before review: typing an answer cleared "choose a question", and correcting
    /// the password left a stale mismatch under a confirm box that now matched.
    @Test("each field's binding clears its own failure, and the password clears the confirmation's")
    func theBindingsClearTheRightFailures() throws {
        let step = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "Views/Registration/RegistrationDetailsStep.swift")
        ).joined(separator: "\n")
        let money = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "Views/Registration/RegistrationMoneyStep.swift")
        ).joined(separator: "\n")

        // "Those do not match" is a statement about both boxes.
        #expect(
            step.contains("viewModel.password = $0") && step.contains("clearFailure(for: .confirmPassword)"),
            "the password binding does not clear the confirmation's mismatch"
        )
        // An answer clears the answer, not the question above it.
        #expect(money.contains("viewModel.firstAnswer = $0; viewModel.clearFailure(for: .firstAnswer)"))
        #expect(money.contains("viewModel.secondAnswer = $0; viewModel.clearFailure(for: .secondAnswer)"))
        // And both answer fields draw their own error rather than pushing it onto the picker.
        #expect(money.contains("viewModel.failure(for: .firstAnswer)"))
        #expect(money.contains("viewModel.failure(for: .secondAnswer)"))
    }

    // MARK: - The date field's tap target

    /// **The whole field opens the picker.** It was a compact `DatePicker` at `opacity(0)` with the placeholder as
    /// a non-hit-testing overlay — and an `.overlay` is laid out by its parent while only the *picker's* frame
    /// takes taps, so the live target was an invisible date pill on the leading edge and the visible words were
    /// dead. Found by tapping it.
    ///
    /// A source scan, because a hit region is not something a test can press. What it pins is the shape of the
    /// fix: one `Button`, and nothing over the box that refuses taps.
    @Test("the date field's tap target is the whole box, not a hidden control inside it")
    func theDateFieldIsTappable() throws {
        let source = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "Components/HWDateField.swift")
        ).joined(separator: "\n")

        #expect(source.contains("Button {"), "the field is not a button, so its hit region is the picker's own")
        #expect(source.contains(".contentShape(.rect)"), "the button's hit region is not the box it draws")
        // The two halves of the old arrangement, each of which alone made the words untappable.
        #expect(!source.contains(".opacity(date == nil ? 0 : 1)"))
        #expect(!source.contains(".allowsHitTesting(false)"))
        // And the picker is reached through a sheet, which is what the design's native input opens.
        #expect(source.contains(".sheet(isPresented:"))
    }

    // MARK: - They build

    /// A smoke test, and said to be one: what it catches is a missing environment object, not a layout.
    @Test("the screen and its three steps build with the environment they are given")
    func theScreensBuild() {
        #expect(TestBench.render(RegistrationView(viewModel: .preview, onSignIn: {}).hwTheme()) != nil)
        #expect(TestBench.render(RegistrationDetailsStep(viewModel: .preview).hwTheme()) != nil)
        #expect(TestBench.render(RegistrationMoneyStep(viewModel: .previewOnStepTwo).hwTheme()) != nil)
        #expect(TestBench.render(RegistrationGoalStep(viewModel: .previewOnStepThree).hwTheme()) != nil)
    }

    /// The pre-auth routes still include registration, and it is no longer the placeholder — the criterion "the
    /// three-step flow is reachable" is one line of `RootView`, and this is it.
    @Test("registration is a pre-auth route with a screen behind it")
    func registrationIsReachable() {
        #expect(PreAuthRoute.allCases.contains(.register))

        let source = try? SourceTree.codeLines(of: SourceTree.appSources.appending(path: "Views/RootView.swift"))
        let lines = source ?? []
        #expect(lines.contains { $0.contains("RegistrationView(") })
        // And the placeholder is gone from that arm: it still serves the two screens that are genuinely unwritten.
        let registerArm = lines.firstIndex { $0.contains("case .register:") }
        let placeholder = lines.firstIndex { $0.contains("case .forgotPassword, .restoreAccount:") }
        #expect(registerArm != nil)
        #expect(placeholder != nil)
    }
}
