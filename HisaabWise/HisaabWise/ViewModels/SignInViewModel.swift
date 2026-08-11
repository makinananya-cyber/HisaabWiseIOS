import Foundation
import Observation

/// What is wrong with the form, or with what the server said about it.
///
/// A value rather than a string, for the reason ``StatePresentation`` is one: "the copy never comes from the
/// server" and "a wrong password does not say whether the account exists" are rules a test can state about a
/// value and cannot state about a rendered sentence (ADR-0016).
enum SignInFailure: Sendable, Equatable {
    /// The email box is empty.
    case emailMissing
    /// The password box is empty.
    case passwordMissing
    /// Under eight characters — **[FIX]** Product Spec §3.2, where the design's sign-in accepted six
    /// (invariant 4: passwords are 8+ everywhere).
    case passwordTooShort
    /// The server refused the credentials. **Deliberately one case for every reason it might have**: a
    /// separate "no such account" would tell an attacker which addresses are registered.
    case credentialsRefused
    /// The account is inside its 30-day deletion grace period (ADR-0015). Its own case because it has a
    /// *flow* rather than a sentence — the user is offered the restore path, not an apology.
    ///
    /// **It carries no date, and that is the gap.** #14 asks for the erase date to be shown; the client
    /// decodes `{error:{code}}` and nothing else (ADR-0016), so the date is not in reach without a `details`
    /// bag on `APIError` — and a bag is how "the client never reads the server's prose" erodes one field at a
    /// time. So the code is handled distinctly and the date arrives with the restore screen (#24), which is
    /// the ticket that owns the grace period. Recorded in `CONTEXT.md` as a change required elsewhere.
    case pendingDeletion
    /// The request could not reach the server. Not a fault, and never rendered as one (ADR-0004).
    ///
    /// **Named `unreachable` rather than `offline` deliberately.** The word `offline` belongs to `LoadState`,
    /// and `StateTaxonomyTests` keeps "only `StateView` switches on the taxonomy" honest with a text scan for
    /// `case .offline` — a second case of that name here would either weaken the scan or fail it. The copy is
    /// still `state.offline`: the user reads the same sentence.
    case unreachable
    /// Anything else the server said, by code. The code chooses the copy; the server's `message` is never
    /// displayed and is never decoded (ADR-0016).
    case refused(ErrorCode)

    /// Which field the failure belongs beside, or `nil` for the ones that belong to the form as a whole.
    ///
    /// Field-level errors are the criterion; this is what decides where each one is drawn, so that a screen
    /// cannot put "wrong password" under the email box.
    var field: SignInField? {
        switch self {
        case .emailMissing: .email
        case .passwordMissing, .passwordTooShort, .credentialsRefused: .password
        case .pendingDeletion, .unreachable, .refused: nil
        }
    }
}

/// The two boxes on the form.
enum SignInField: Sendable, Equatable, CaseIterable {
    case email
    case password
}

/// Sign in: two fields, one choice, and one request.
///
/// **Not a ``BaseViewModel``**, for the reason ``LandingViewModel`` is not: that protocol is one *read* and the
/// mapping of its outcome to a ``LoadState``, and this screen writes. Its states are a form's — invalid, in
/// flight, refused — and none of them is `empty` or `loaded`.
///
/// **It does not talk to the client.** `SessionCoordinator.signIn(email:password:keepMeSignedIn:)` already owns
/// the request *and* the decision that ADR-0007 cares about: the refresh token goes to the Keychain when the box
/// is checked and to memory when it is not. This view model owns the form, and asks the coordinator to sign in.
///
/// **It maps an `APIError` to a ``SignInFailure``, which is a second mapping owner and is argued rather than
/// smuggled.** `BaseViewModel.load()` is the only place an error becomes a ``LoadState``; a form error is not a
/// `LoadState`, and there is no third place. `StateTaxonomyTests` names both owners.
@MainActor
@Observable
final class SignInViewModel {
    /// Product Spec §3.2 **[FIX]**: the identifier is the email. The design's sign-in asks for a username and
    /// registration never collects one, so there is nothing for a username to be (invariant 4).
    var email = ""
    var password = ""

    /// **Checked by default**, as the design draws it. What it decides is which `TokenStore` the session lands
    /// in, which is ADR-0007's whole distinction: the Keychain survives a relaunch, memory ends with the
    /// process.
    var keepMeSignedIn = true

    private(set) var failures: [SignInFailure] = []
    private(set) var isSigningIn = false

    /// How many times the *server* has refused these credentials in this session.
    ///
    /// It drives one thing: after three, the screen offers a way to contact support. It does **not** gate
    /// submission and it does not back off — "server-side backoff is authoritative and the client never counts
    /// on its own" (#14). A client that locked its own user out would be a client that a reinstall unlocks.
    private(set) var refusals = 0

    /// After three refusals, suggest support. Read by the view; counted here so a test can drive it.
    var suggestsSupport: Bool { refusals >= Self.refusalsBeforeSupport }

    static let refusalsBeforeSupport = 3

    /// Invariant 4 — 8+ characters, everywhere.
    static let minimumPasswordLength = 8

    private let session: SessionCoordinator

    init(session: SessionCoordinator) {
        self.session = session
    }

    /// The failure to draw beside one field, if any.
    func failure(for field: SignInField) -> SignInFailure? {
        failures.first { $0.field == field }
    }

    /// The failure that belongs to the form rather than to a field — offline, refused, pending deletion.
    var formFailure: SignInFailure? {
        failures.first { $0.field == nil }
    }

    /// Signs in, or explains why it did not.
    ///
    /// Local validation first, because a request that the client already knows will fail is a round trip the
    /// user waits for. Then the coordinator, whose success has one visible consequence: `isSignedIn` flips and
    /// the root swaps Landing for the shell (ADR-0026) — this screen does not navigate, and holds no route.
    func signIn() async {
        failures = validate()
        guard failures.isEmpty else { return }

        isSigningIn = true
        defer { isSigningIn = false }

        do {
            try await session.signIn(email: email, password: password, keepMeSignedIn: keepMeSignedIn)
        } catch {
            let failure = Self.failure(for: error)
            // Only a *refusal* counts. A tunnel is not a wrong password, and counting it would offer support
            // to somebody whose only problem is the Underground.
            if failure == .credentialsRefused { refusals += 1 }
            failures = [failure]
        }
    }

    /// Clears the failure on a field the user is editing, so a corrected box stops being red while they type.
    func clearFailure(for field: SignInField) {
        failures.removeAll { $0.field == field }
    }

    // MARK: - What is wrong

    private func validate() -> [SignInFailure] {
        var failures: [SignInFailure] = []

        // Trimmed for emptiness only. **The client does not validate the shape of an email address**: every
        // regex is wrong about somebody's real address, and the server has to check it anyway.
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failures.append(.emailMissing)
        }
        if password.isEmpty {
            failures.append(.passwordMissing)
        } else if password.count < Self.minimumPasswordLength {
            failures.append(.passwordTooShort)
        }

        return failures
    }

    /// An error from the sign-in request, as a failure the form can draw.
    ///
    /// `static` and pure so it is testable without a coordinator: every branch here is a rule, and a rule
    /// worth writing down is worth asserting.
    static func failure(for error: any Error) -> SignInFailure {
        guard let apiError = error as? APIError else { return .refused(.unknown) }

        switch apiError {
        case .offline:
            return .unreachable
        case .malformedResponse:
            return .refused(.malformedResponse)
        case .unauthenticated:
            // A 401 on the sign-in route means "these credentials are wrong", not "your session expired" —
            // there is no session yet to expire (`APIClient.Authorization`).
            return .credentialsRefused
        case .server(let status, let code):
            if code == .accountPendingDeletion {
                return .pendingDeletion
            }
            // **Inverted on purpose: everything is a refusal unless it is a known fault.** Listing the refusal
            // statuses instead — 401 and 403, as the first version of this did — leaves every other status a
            // hole: a `404 NO_SUCH_ACCOUNT` would fall through to its own copy and turn the form into an
            // address checker. The faults are the ones a *user* cannot cause, and they are enumerable.
            return Self.isFault(status: status) ? .refused(code) : .credentialsRefused
        }
    }

    /// Whether a status from the login route describes something wrong with the *server or the request* rather
    /// than with the credentials. Everything else is a refusal, and every refusal reads the same.
    private static func isFault(status: Int) -> Bool {
        // 5xx is the server's own problem; 429 is the backoff that is authoritative (#14); 400 is a request the
        // client built wrongly, which is a bug rather than a wrong password.
        status >= 500 || status == 429 || status == 400
    }
}
