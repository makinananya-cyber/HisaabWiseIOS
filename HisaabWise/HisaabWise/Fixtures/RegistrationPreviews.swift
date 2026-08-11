#if DEBUG
import SwiftUI

/// The registration form in every state its three screens have, for the previews.
///
/// Here rather than beside the views for the reason `PreviewSession` gives: assembling a client is not a view's
/// business, and `LayeringTests` asserts that no file under `Views/` names `APIClient`, `Transport`, or a
/// `ContentLoader` (which is one `load` away from being both).
///
/// **Every state is reached by driving the object**, not by setting private state: the lists are loaded through a
/// `FixtureTransport`, the steps are advanced through `advance()`, and a refused submit is a real `409` on the
/// wire. A preview built on a fabricated flag keeps rendering after the real path stops working, which is what
/// ADR-0013 is about.
extension RegistrationViewModel {
    /// The three reference-list payloads, served as a content route serves them.
    private static var referenceFixtures: [Fixture] {
        [.referenceCountries, .referenceCurrencies, .referenceSecurityQuestions]
    }

    /// Step 1, empty, with the lists loaded and the design's defaults applied.
    @MainActor
    static var preview: RegistrationViewModel {
        make(loadingLists: true)
    }

    /// Step 1 with every box filled and a strong password — the state the Register button is meant to be pressed
    /// in.
    @MainActor
    static var previewFilledStepOne: RegistrationViewModel {
        make(loadingLists: true) { $0.fillStepOne() }
    }

    /// Step 1 with every rule broken at once: no name, a bad address, a two-digit phone number, no date of birth,
    /// a short password that its confirmation does not match, and the Terms unticked.
    @MainActor
    static var previewFailedStepOne: RegistrationViewModel {
        make(loadingLists: true) { viewModel in
            viewModel.email = "not-an-address"
            viewModel.phoneDigits = "12"
            viewModel.password = "short"
            viewModel.confirmPassword = "shorter"
            viewModel.advance()
        }
    }

    /// Step 2, reached by filling step 1 and advancing — so the step bar, the copy, and the dots are all in the
    /// state the real flow puts them in.
    @MainActor
    static var previewOnStepTwo: RegistrationViewModel {
        make(loadingLists: true) { $0.fillStepOne(); $0.advance() }
    }

    /// Step 2 with a salary and both questions answered.
    @MainActor
    static var previewFilledStepTwo: RegistrationViewModel {
        make(loadingLists: true) { $0.fillStepOne(); $0.advance(); $0.fillStepTwo() }
    }

    /// Step 2 submitted empty, so every field on it is marked.
    @MainActor
    static var previewFailedStepTwo: RegistrationViewModel {
        make(loadingLists: true) { $0.fillStepOne(); $0.advance(); $0.advance() }
    }

    /// Step 3, pre-filled with 20% of the salary as `advance()` fills it.
    @MainActor
    static var previewOnStepThree: RegistrationViewModel {
        make(loadingLists: true) { $0.fillStepOne(); $0.advance(); $0.fillStepTwo(); $0.advance() }
    }

    /// Step 3 with a goal above the 20% rule — the "ahead of the rule" hint, and the suggestion offered.
    @MainActor
    static var previewGoalAboveTheRule: RegistrationViewModel {
        make(loadingLists: true) { $0.reachStepThree(); $0.editGoal("2500") }
    }

    /// Step 3 with a goal under the rule.
    @MainActor
    static var previewGoalBelowTheRule: RegistrationViewModel {
        make(loadingLists: true) { $0.reachStepThree(); $0.editGoal("500") }
    }

    /// Step 3 with the box cleared, which is the state that points at Skip.
    @MainActor
    static var previewGoalEmpty: RegistrationViewModel {
        make(loadingLists: true) { $0.reachStepThree(); $0.editGoal("") }
    }

    /// The lists refused — a transport that answers nothing, which is the state the retry exists for.
    @MainActor
    static var previewWithoutReferenceLists: RegistrationViewModel {
        make(loadingLists: false)
    }

    // MARK: - Building one

    /// - Parameter prepare: run **after the lists have arrived**, and that ordering is the whole reason this takes
    ///   a closure rather than each factory mutating the object it was handed. Filling step 2 before the question
    ///   bank exists chooses `questions.first` of an empty array — so a "filled" preview drew an unchosen
    ///   question, which is exactly the state it was written to rule out.
    @MainActor
    private static func make(
        loadingLists: Bool,
        prepare: (@MainActor (RegistrationViewModel) -> Void)? = nil
    ) -> RegistrationViewModel {
        let transport: FixtureTransport
        if loadingLists {
            guard let serving = try? FixtureTransport.serving(referenceFixtures) else {
                // Trapping rather than previewing the empty form: a missing fixture file is a bundle assembled
                // wrong, it reproduces in every preview, and a canvas that silently shows the other branch is how
                // nobody finds out (the reasoning `PreviewSession` gives).
                preconditionFailure("A preview fixture is missing: \(referenceFixtures.map(\.rawValue))")
            }
            transport = serving
        } else {
            transport = FixtureTransport(stubs: [:])
        }

        let language = LanguageManager(selected: .english)
        let client = APIClient(
            baseURL: URL(string: "https://fixtures.invalid")!,
            transport: transport,
            language: language,
            refreshTokens: InMemoryTokenStore()
        )
        let viewModel = RegistrationViewModel(
            session: SessionCoordinator(
                client: client,
                keptStore: InMemoryTokenStore(),
                transientStore: InMemoryTokenStore()
            ),
            // In memory, so drawing a preview leaves nothing in the Caches directory of the machine drawing it.
            content: ContentLoader(client: client, store: InMemoryContentStore()),
            language: language,
            // The placeholder domain the `.xcconfig` files carry until Rule 7's credentials arrive.
            legal: LegalLinks(
                terms: URL(string: "https://hisaabwise.invalid/terms")!,
                privacy: URL(string: "https://hisaabwise.invalid/privacy")!
            )
        )
        // The lists arrive a frame later, exactly as they do in the app: `RegistrationView`'s own `.task` is what
        // loads them there, and a preview that pre-loaded them synchronously would not exercise the empty frame.
        Task {
            await viewModel.loadReferenceLists()
            prepare?(viewModel)
        }
        return viewModel
    }

    /// Sample details, sitting in the same fields the user types into. **Not the design's `?demo` block**, which
    /// the content rules mark for deletion: that filled a live form on a shipped page, and this is preview-only
    /// scaffolding behind `#if DEBUG`.
    @MainActor
    fileprivate func fillStepOne() {
        name = "Neeraj Makin"
        email = "neeraj@example.ae"
        phoneDigits = "501234567"
        dateOfBirth = RegistrationViewModel.dateOfBirthRange().lowerBound.addingTimeInterval(60 * 60 * 24 * 365 * 90)
        password = "a-long-enough-password-1!"
        confirmPassword = "a-long-enough-password-1!"
        acceptedTerms = true
    }

    /// Steps 1 and 2 filled and advanced twice — the way step 3's own previews get there.
    @MainActor
    fileprivate func reachStepThree() {
        fillStepOne()
        advance()
        fillStepTwo()
        advance()
    }

    @MainActor
    fileprivate func fillStepTwo() {
        salaryText = "8000"
        firstQuestion = questions.first
        firstAnswer = "Al Noor"
        secondQuestion = questions.dropFirst().first
        secondAnswer = "Dubai"
    }
}

/// The ground a registration step is previewed on: the brand gradient, the screen's own insets, and the theme.
///
/// A step is a fragment of ``RegistrationView`` — it has no background of its own, because the screen owns it —
/// so previewing one without this shows dark text on a white canvas and proves nothing about legibility.
struct RegistrationStepPreview<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 22)
                .padding(.vertical, 26)
        }
        .background(HWBrandGround())
        .hwTheme()
    }
}
#endif
