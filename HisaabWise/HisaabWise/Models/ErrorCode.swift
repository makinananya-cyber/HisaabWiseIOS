/// A server error's machine-readable `code`, and nothing else.
///
/// ADR-0016 — **the server's `message` field is never displayed.** English prose reaching an
/// Arabic-reading user in every failure state is the defect this prevents, so the client carries the
/// code and maps it to localised copy in one place. The envelope's `message` is not merely unused
/// here; it is never decoded, so there is nothing to display by accident.
///
/// Open-ended rather than a closed `enum`: a code the client has never heard of must still arrive
/// intact and fall through to generic copy. The code-to-copy mapping itself lands with the design
/// system.
struct ErrorCode: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

extension ErrorCode: Decodable {
    init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
}

/// The codes this build recognises.
///
/// Naming one here is not the same as giving it copy — that is `ErrorCopy`'s job, and a code with no
/// entry there reads as generic. A constant earns its place when code refers to the code itself.
extension ErrorCode {
    /// The fallback when a response carries no usable code, or one the client cannot recognise.
    static let unknown = ErrorCode(rawValue: "UNKNOWN")

    /// The response body did not match the shape the client decodes. Client-side: no server sends it.
    static let malformedResponse = ErrorCode(rawValue: "MALFORMED_RESPONSE")

    /// The request needed a session and there was none left to present (ADR-0007). Client-side: the
    /// server's own 401 carries whatever code it likes, and this is what the client says when it did not
    /// get as far as asking.
    static let unauthenticated = ErrorCode(rawValue: "UNAUTHENTICATED")

    /// Too many requests in the window (Technical Spec §7's rate limiting).
    static let rateLimited = ErrorCode(rawValue: "RATE_LIMITED")

    /// The write was addressed to a month the rollover has since archived. Still live with no write
    /// queue in the app: a request in flight across the boundary, or a client left open past midnight
    /// on the 1st, still hits it (Product Spec §4.5, ADR-0019).
    static let monthClosed = ErrorCode(rawValue: "MONTH_CLOSED")

    /// The account is inside its 30-day deletion grace period, and signing in is an offer to restore it rather
    /// than a failure (ADR-0015). **Deliberately absent from `ErrorCopy`**: a code with a *flow* rather than a
    /// sentence is handled by the screen that owns the flow — sign-in offers the restore path (#14), and #24
    /// draws the screen behind it.
    static let accountPendingDeletion = ErrorCode(rawValue: "ACCOUNT_PENDING_DELETION")

    /// The `currentPassword` on a password change was wrong (#23).
    ///
    /// **Not in `ErrorCopy`**, for the reason `EMAIL_TAKEN` is not: it is a *field* error on the first step of a
    /// flow, and the screen that owns the flow draws it — the copy belongs beside the box, not in a placeholder
    /// where the screen used to be.
    ///
    /// It is also why the password change is one request rather than three (``PasswordChange``): a route that
    /// answered this question *before* being told the new password would be a password-checking oracle.
    ///
    /// **The route must carry it on a `422`, never a `401`** — a constraint on the backend, found by writing the
    /// test for it. A `401` is answered by refreshing and retrying once (ADR-0007), and a refresh that the server
    /// then refuses ends the session and clears the store: on a rotating token family, a mistyped current password
    /// would sign the user out. `422` is what the client can read as "that field was wrong".
    static let invalidCredentials = ErrorCode(rawValue: "INVALID_CREDENTIALS")

    /// One or both security answers did not match the stored hashes (§4.3, invariant 5, #23).
    ///
    /// **It does not say which**, and the server must not: answers are compared as argon2id hashes of a
    /// normalised form, and telling somebody which of two guesses landed is a hint to whoever is guessing. The
    /// design reddens the specific field because it compared the raw strings in the browser, which is defect D4.
    static let securityAnswersInvalid = ErrorCode(rawValue: "SECURITY_ANSWERS_INVALID")

    /// Registration refused because the email already has an account.
    ///
    /// **The only way the client ever learns an address is taken**, and only in response to a submission the user
    /// made — there is deliberately no email-availability endpoint, because one would answer "does this person
    /// bank here" to anybody who asked (#15). Not in `ErrorCopy` either: it is a *field* error on step 1, which
    /// the screen that owns the form draws.
    static let emailTaken = ErrorCode(rawValue: "EMAIL_TAKEN")

    /// Too many failed attempts against this account, on a `429`.
    ///
    /// **Recovery keeps its own counters, separate from sign-in's**, which matters more than it sounds: recovery
    /// is the only way back into an account, so sharing login's lockout would let a stranger's failed password
    /// guesses lock the real owner out of their own recovery.
    ///
    /// The backoff is the server's and it is authoritative — the client shows this and never counts on its own,
    /// because a client-side lockout is one a reinstall lifts.
    static let accountLocked = ErrorCode(rawValue: "ACCOUNT_LOCKED")

    /// The single-use password-reset ticket has been spent or has expired.
    ///
    /// Recoverable rather than fatal: the reader answers their questions again and gets a new one. The screen
    /// sends them back a step rather than leaving a button that cannot succeed.
    static let resetTicketInvalid = ErrorCode(rawValue: "RESET_TICKET_INVALID")
}
