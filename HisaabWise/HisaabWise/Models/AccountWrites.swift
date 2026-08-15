import Foundation

/// `PUT /v1/me` — the three editable personal details, together.
///
/// **`PUT` rather than the Technical Spec's `PATCH`**, and the reason is what the design's Save button does:
/// it commits the whole `#pi` card at once, so every field the route accepts is in every request and there is
/// no partial update to express. A `PATCH` would also be a fifth verb on `APIClient` — a fifth set of rules
/// about idempotency keys and cache bypass to reason about — bought for one route that has nothing to
/// distinguish "left alone" from "set to this".
///
/// **Email is not a field here, and that absence is the point** (invariant 4). It is the identity, it is
/// locked on the screen, and the route cannot change it — so there is nothing for a client bug, a rogue view,
/// or a future refactor to send. `AccountViewModelTests` asserts the absence against the bytes on the wire
/// rather than against this type, because a `Encodable` that stopped encoding a field would still compile.
///
/// Answers with the **updated screen payload** (ADR-0020), so the profile header, the row subtitles, and the
/// salary's display string all come back computed rather than being patched here.
struct PersonalDetailsUpdate: Sendable, Hashable, Encodable {
    /// "Username" on the screen. A display name, never an identifier.
    let displayName: String

    /// `{minor, currency}` — never a bare number (invariant 1), and never a figure that has been through a
    /// display formatter (defect D16). The currency is the one the salary was **authored** in, because money
    /// is stored as authored and there is no storage base (§4.1 **[FIX]**).
    let salary: MoneyAmount

    /// Absent rather than empty when the user has not given one, exactly as registration sends it
    /// (ADR-0031).
    let phone: PhoneNumber?
}

/// `PUT /v1/me/currency` — the display currency.
///
/// **The ISO code and nothing else.** The symbol and the name are presentation and stay on the client, which
/// is the same rule `RegistrationRequest.displayCurrency` follows.
///
/// A `PUT` because it replaces a value, so it carries no `Idempotency-Key` (ADR-0022). Answering with the
/// screen payload is what makes the change visible without a patch — and what the app-wide repaint is *for*
/// is every **other** screen, whose figures were converted at read in the old currency (ADR-0003).
struct DisplayCurrencyUpdate: Sendable, Hashable, Encodable {
    let currency: String
}

/// `POST /v1/me/password` — the current password, both security answers, and the new password, in **one**
/// request.
///
/// **One request rather than three, and this is the decision worth reading.** The design walks three steps and
/// verifies each one in the browser: the current password against nothing at all, and the answers against
/// `state.security[i].answer` held in memory — which is defect D4, and which invariant 5 makes the server's
/// job. Once verification is server-side, a step-by-step flow needs the server to *remember* that this session
/// got past step one, which is a session-scoped verification state nothing else in this app has.
///
/// And it would be a worse thing to have than to do without: a route that answers "is this the right current
/// password?" before being told what to change it to is a password-checking oracle behind a session, which is
/// the same class of thing the email-availability route was refused for (#15). So the three steps are the
/// client's sequencing of one submission — nothing exists server-side until the last button, exactly as
/// registration decided (ADR-0031) — and the refusal names which part was wrong.
///
/// **Changing the password revokes every other session** (Product Spec §3.7 **[FIX]**), which is the server's
/// half and needs nothing from the client: the requesting family survives, and if the server ends this session
/// too, the `securityEpoch` bump reaches the client as a `401` and ADR-0007's hard-logout path is already what
/// handles it.
///
/// **And the refusals come on a `422`, never a `401`** — `ErrorCode.invalidCredentials` records why, and it is the
/// one constraint this route places on the backend that is not visible from the body: on this client a `401` means
/// "your token is no good", so it spends the refresh token, and against a rotating family a mistyped current
/// password could end the session.
struct PasswordChange: Sendable, Hashable, Encodable {
    /// What the user signs in with today. Sent, not verified here: the client holds no hash and no salt, and
    /// checking a password locally is the defect (D4).
    let currentPassword: String

    /// Exactly two, keyed by question id (§4.3 **[FIX]**, D12).
    ///
    /// **The typed answer travels; the *stored* answer never leaves the server.** §4.3 normalises to a
    /// canonical form and compares argon2id hashes, and both halves of that are server-side — a client that
    /// normalised first would be a second owner of the canonical form, and a client that hashed would need
    /// the per-user salt.
    let securityAnswers: [SecurityAnswer]

    /// 8+ characters everywhere (invariant 4). Refused locally before it is sent, and refused again by the
    /// server, because a client-side length check is a courtesy and not a rule.
    let newPassword: String
}

/// What `DELETE /v1/me` answers with.
///
/// **Decoded and then discarded**, which looks pointless and is not: `APIClient.delete` requires a response type
/// because a delete on this API returns the state the deletion produced (ADR-0020), and declaring the shape is
/// what makes a route that starts answering with something else a decode failure rather than a silent success.
///
/// The grace period is the reason there is anything here at all: the account is soft-deleted and erased after
/// `purgeAfterDays` (ADR-0015). The screen does not draw these fields — it signs out — but the server's own
/// sentence is the one the restore flow will need when #24 lands, so the contract is written down now.
struct AccountDeletion: Sendable, Decodable {
    let deletedAt: String
    let purgeAfterDays: Int
}

/// The body of `POST /v1/me/password/check` — "is what I have typed so far right?"
///
/// **Advisory.** It writes nothing, and `POST /v1/me/password` re-verifies every field, so this changes when the
/// reader is told rather than what the server trusts. Sending it is what stops the wizard collecting three screens
/// of input before mentioning that the first box was wrong.
///
/// `securityAnswers` is `nil` on step one, where the only thing to check is the password. `Encodable` omits it, so
/// the server reads "only check the password" from the shape of the request rather than from a flag.
struct PasswordCheck: Sendable, Encodable {
    let currentPassword: String
    let securityAnswers: [SecurityAnswer]?
}

/// What the check answers with when it accepts. **The body carries nothing worth reading** — the status is the
/// answer, and a refusal arrives as an `APIError` rather than as a field in here.
struct PasswordCheckAccepted: Sendable, Decodable {}

/// The body of `PUT /v1/me/goal` — a savings goal the reader has chosen.
///
/// **In the salary's currency**, which the server checks: the pair is compared by the budget engine, and two
/// currencies would make `saved` a conversion rather than a subtraction.
struct SavingsGoalUpdate: Sendable, Encodable {
    let savingsGoal: MoneyAmount
}
