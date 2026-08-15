import Foundation
import Observation

/// Which of recovery's three questions the reader is on.
///
/// A stage rather than a set of booleans, for the reason ``PreAuthRoute`` is a path: each step is a case, and
/// "which step am I on" has exactly one answer at a time.
enum RecoveryStage: Int, Sendable, Equatable, CaseIterable, Comparable {
    /// Who are you — the address the account was made with.
    case email
    /// Prove it — the two questions this account was set up with, the answers, and the date of birth.
    case identity
    /// Choose a new password.
    case newPassword

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What is wrong with the recovery form, or with what the server said about it.
///
/// A value, not a sentence, for the same reason ``SignInFailure`` is one: "it never says which factor missed"
/// is a rule worth asserting, and a rendered string cannot be asserted about (ADR-0016).
enum RecoveryFailure: Sendable, Equatable {
    case emailMissing
    case answerMissing
    case dateOfBirthMissing
    case passwordMissing
    case passwordTooShort
    case passwordsDiffer

    /// The server refused the identity check.
    ///
    /// **One case for all three factors.** The server does not say whether the date of birth or one of the two
    /// answers was wrong, and it must not: telling somebody which of two guesses landed halves the work of
    /// guessing the other. So there is nowhere for this to be more specific, and nothing here to make it look
    /// as if there were.
    case identityRefused
    /// Too many attempts. The server's own backoff is authoritative; the client never counts on its own.
    case locked
    /// The ticket expired between verifying and choosing a password. Recoverable by starting again.
    case ticketExpired
    case unreachable
    case refused(ErrorCode)

    /// Which box the failure belongs beside, or `nil` when it belongs to the form.
    var field: RecoveryField? {
        switch self {
        case .emailMissing: .email
        case .answerMissing: .answers
        case .dateOfBirthMissing: .dateOfBirth
        case .passwordMissing, .passwordTooShort: .newPassword
        case .passwordsDiffer: .confirmPassword
        case .identityRefused, .locked, .ticketExpired, .unreachable, .refused: nil
        }
    }
}

/// Every box recovery draws, so a failure can say which one it belongs beside.
enum RecoveryField: Sendable, Equatable, CaseIterable {
    case email, answers, dateOfBirth, newPassword, confirmPassword
}

/// Recovery by security question — the way back into an account when the password is gone.
///
/// **This is the only way back in.** There is no OTP and no email verification anywhere in this product, so
/// two security answers plus a date of birth are the whole of it. That shapes three decisions here:
///
///   - **Both answers matter, and both are sent.** The server holds a hash of each and verifies both,
///     whatever the first one said, so the timing does not reveal which failed.
///   - **The date of birth is a third factor, not a formality.** Two low-entropy answers alone would be thin
///     defence on an app holding somebody's salary, and the unverified email address is not even a channel
///     for warning the real owner that a recovery was attempted.
///   - **An unknown address still gets two questions.** The server answers with plausible decoys rather than
///     an error, so this screen cannot be used to ask "does this person have an account" — which means the
///     client must not treat reaching stage two as proof the account exists, and nothing here does.
@MainActor
@Observable
final class ForgotPasswordViewModel {
    // MARK: - What the reader has typed

    var email = ""
    /// One per question, in the order the server listed them. Sized when the questions arrive.
    var answers: [String] = []
    var dateOfBirth: Date?
    var newPassword = ""
    var confirmPassword = ""

    // MARK: - What the server has said

    private(set) var stage: RecoveryStage = .email
    /// The two questions this account was set up with — **server content**, in the reader's language.
    private(set) var questions: [SecurityQuestion] = []
    private(set) var failures: [RecoveryFailure] = []
    private(set) var isWorking = false
    /// True once the password has been reset, which is the screen's one terminal state.
    private(set) var didReset = false

    /// How many times the server has refused the identity check in this visit. After three, offer support —
    /// the same threshold sign-in uses, and for the same reason: it is the only thing left that helps somebody
    /// who cannot answer their own questions.
    private(set) var refusals = 0
    var suggestsSupport: Bool { refusals >= 3 }

    /// Invariant 4 — 8+ characters, everywhere.
    static let minimumPasswordLength = 8

    /// The single-use ticket the identity check issues. **Never rendered and never persisted**: it is a
    /// credential, and it lives exactly as long as this screen does.
    private var ticket: String?

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func failure(for field: RecoveryField) -> RecoveryFailure? {
        failures.first { $0.field == field }
    }

    /// The failure that belongs to the form rather than to a box.
    var formFailure: RecoveryFailure? {
        failures.first { $0.field == nil }
    }

    func clearFailure(for field: RecoveryField) {
        failures.removeAll { $0.field == field }
    }

    // MARK: - Stage one — the address

    /// Asks which two questions this account was set up with.
    ///
    /// A refusal here is a *fault*, never "no such account": the route answers with decoys for an address it
    /// does not know, so there is no not-found case to handle and this screen cannot become an address checker.
    func lookUpQuestions() async {
        failures = validateEmail()
        guard failures.isEmpty else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            let response = try await client.post(
                Endpoint.forgotPasswordQuestions,
                body: QuestionsRequest(email: email.trimmed),
                authorization: .anonymous,
                as: SecurityQuestionList.self
            )
            questions = response.questions
            answers = Array(repeating: "", count: response.questions.count)
            stage = .identity
        } catch {
            failures = [Self.failure(for: error)]
        }
    }

    // MARK: - Stage two — the three factors

    /// Verifies the answers and the date of birth, and holds the ticket that comes back.
    func verifyIdentity() async {
        failures = validateIdentity()
        guard failures.isEmpty else { return }

        guard let dateOfBirth else { return }

        isWorking = true
        defer { isWorking = false }

        let submitted = zip(questions, answers).map { question, answer in
            SubmittedAnswer(questionId: question.id, answer: answer.trimmed)
        }

        do {
            let response = try await client.post(
                Endpoint.forgotPasswordVerify,
                body: VerifyRequest(
                    email: email.trimmed,
                    dateOfBirth: Self.dayFormatter.string(from: dateOfBirth),
                    answers: submitted
                ),
                authorization: .anonymous,
                as: TicketResponse.self
            )
            ticket = response.ticket
            stage = .newPassword
        } catch {
            let failure = Self.failure(for: error)
            // Only a *refusal* counts towards offering support. A tunnel is not a wrong answer.
            if failure == .identityRefused { refusals += 1 }
            failures = [failure]
        }
    }

    // MARK: - Stage three — the new password

    /// Spends the ticket and sets the password.
    ///
    /// Success signs **every** device out, including any the attacker had — which is the same rule in both
    /// directions, and the reason this screen ends by sending the reader to sign in rather than straight in.
    func resetPassword() async {
        failures = validateNewPassword()
        guard failures.isEmpty else { return }

        guard let ticket else {
            // No ticket means the verify step was never completed. Send them back to earn one rather than
            // posting a request that cannot succeed.
            failures = [.ticketExpired]
            stage = .identity
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await client.post(
                Endpoint.resetPassword,
                body: ResetRequest(ticket: ticket, newPassword: newPassword),
                authorization: .anonymous,
                as: ResetResponse.self
            )
            self.ticket = nil
            didReset = true
        } catch {
            let failure = Self.failure(for: error)
            if failure == .ticketExpired {
                // The ticket is single-use and short-lived. Starting again at the identity step is the only
                // thing that can help, so the screen goes there rather than leaving a dead button.
                self.ticket = nil
                stage = .identity
            }
            failures = [failure]
        }
    }

    // MARK: - What is wrong

    private func validateEmail() -> [RecoveryFailure] {
        // Emptiness only. **The client does not validate the shape of an email address**: every regex is
        // wrong about somebody's real address, and the server checks it anyway.
        email.trimmed.isEmpty ? [.emailMissing] : []
    }

    private func validateIdentity() -> [RecoveryFailure] {
        var failures: [RecoveryFailure] = []
        // **Every** answer, not just the first: a blank second box was the shape of a defect that made
        // registration impossible to finish, and the same box exists here.
        if answers.isEmpty || answers.contains(where: { $0.trimmed.isEmpty }) {
            failures.append(.answerMissing)
        }
        if dateOfBirth == nil {
            failures.append(.dateOfBirthMissing)
        }
        return failures
    }

    private func validateNewPassword() -> [RecoveryFailure] {
        var failures: [RecoveryFailure] = []
        if newPassword.isEmpty {
            failures.append(.passwordMissing)
        } else if newPassword.count < Self.minimumPasswordLength {
            failures.append(.passwordTooShort)
        } else if confirmPassword != newPassword {
            failures.append(.passwordsDiffer)
        }
        return failures
    }

    /// An error from any of the three requests, as a failure the form can draw.
    ///
    /// `static` and pure so every branch is assertable without a client.
    static func failure(for error: any Error) -> RecoveryFailure {
        guard let apiError = error as? APIError else { return .refused(.unknown) }

        switch apiError {
        case .offline:
            return .unreachable
        case .malformedResponse:
            return .refused(.malformedResponse)
        case .unauthenticated:
            // These routes are anonymous, so a 401 is not "your session expired" — there is no session. Read
            // as a refusal, which is the safe reading and the one that says nothing extra.
            return .identityRefused
        case .server(let status, let code):
            switch code {
            case .securityAnswersInvalid: return .identityRefused
            case .accountLocked: return .locked
            case .resetTicketInvalid: return .ticketExpired
            default:
                // Everything that is not a known fault reads as a refusal, for the reason sign-in inverts the
                // same test: listing refusal statuses leaves every other status a hole, and a hole here would
                // turn this screen into an account-existence oracle.
                return Self.isFault(status: status) ? .refused(code) : .identityRefused
            }
        }
    }

    private static func isFault(status: Int) -> Bool {
        status >= 500 || status == 429 || status == 400
    }

    /// `YYYY-MM-DD`, in UTC, which is the shape the server parses a calendar date in.
    ///
    /// Fixed locale and fixed zone: a date of birth is a calendar fact, and formatting it in the reader's
    /// locale would send `١٩٩٣` or shift the day across a zone boundary.
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - The wire

    private struct QuestionsRequest: Encodable, Sendable {
        let email: String
    }

    private struct SubmittedAnswer: Encodable, Sendable {
        let questionId: String
        let answer: String
    }

    private struct VerifyRequest: Encodable, Sendable {
        let email: String
        let dateOfBirth: String
        let answers: [SubmittedAnswer]
    }

    private struct TicketResponse: Decodable, Sendable {
        let ticket: String
    }

    private struct ResetRequest: Encodable, Sendable {
        let ticket: String
        let newPassword: String
    }

    /// The reset route answers with a token pair. **Deliberately discarded**: a recovery signs every device
    /// out, so signing this one straight back in would be the one exception, and the reader is sent to the
    /// sign-in form to use the password they just chose.
    private struct ResetResponse: Decodable, Sendable {}
}

// Previews live in `Fixtures/ForgotPasswordPreviews.swift`, for the reason `RegistrationPreviews` gives:
// assembling a client is not a view model's business either, and every preview state is reached by driving
// the object over a `FixtureTransport` rather than by setting private state (ADR-0013).
