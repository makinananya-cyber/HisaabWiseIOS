import Foundation

/// The one place a server error code becomes something a person reads.
///
/// ADR-0016 — **the server's `message` field is never displayed.** English prose reaching an
/// Arabic-reading user in every failure state is the defect this prevents, and the client's half of
/// that bargain is that it never decodes `message` at all (see ``APIError``). What it does carry is the
/// machine-readable `code`, and this is where that code turns into localised copy.
///
/// **An unrecognised code is the normal case, not an error case.** The backend will ship codes this
/// build has never heard of, and the only acceptable answer is ``generic`` — never the raw code, never
/// an empty string, never a crash.
///
/// Deliberately *not* exhaustive. A code only earns an entry here when its copy tells the user
/// something ``generic`` does not. Codes with a flow of their own rather than a message —
/// `ACCOUNT_PENDING_DELETION` gets the restore screen and its erase date (ADR-0015, issue #24) — are
/// not `StateView` copy and are absent on purpose.
enum ErrorCopy {
    /// What an unmapped code reads as. Says that something failed and that trying again is reasonable,
    /// which is all that is true of a code nobody here recognises.
    static let generic: LocalizedStringResource = "state.failed.generic"

    /// Codes with copy of their own. The table *is* the mapping — there is no second `switch`
    /// anywhere, which is what makes the "exactly one place" claim checkable rather than aspirational.
    private static let table: [ErrorCode: LocalizedStringResource] = [
        .malformedResponse: "state.failed.malformedResponse",
        .rateLimited: "state.failed.rateLimited",
        .monthClosed: "state.failed.monthClosed",
    ]

    /// The codes with copy of their own, for the suite that checks each has English behind it.
    static var recognisedCodes: [ErrorCode] {
        table.keys.sorted { $0.rawValue < $1.rawValue }
    }

    static func message(for code: ErrorCode) -> LocalizedStringResource {
        table[code] ?? generic
    }
}
