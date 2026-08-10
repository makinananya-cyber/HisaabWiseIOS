/// The state every screen's data goes through.
///
/// ADR-0016 — one taxonomy, so that five tabs times four data states do not become twenty screens
/// of bespoke copy and bespoke VoiceOver. Two rules travel with it:
///
/// - **`offline` is never rendered as `failed`.** Offline is a supported mode (ADR-0004), not a
///   fault, and telling a user something broke when the app is working as designed is the defect.
/// - **`failed` carries a code, never server prose** — see ``ErrorCode``.
enum LoadState<Value: Sendable>: Sendable {
    /// No data yet, and a request is expected to produce some.
    case loading
    /// The request succeeded and there is genuinely nothing to show.
    case empty
    /// The request could not reach the server. The session survives; the last-received figures
    /// remain valid for the currency then in force.
    case offline
    /// The server answered definitively, and unsuccessfully.
    case failed(ErrorCode)
    /// Data.
    case loaded(Value)
}

extension LoadState {
    /// The loaded value, or `nil` in every other state.
    var value: Value? {
        guard case .loaded(let value) = self else { return nil }
        return value
    }

    /// Distinguishing these two is the whole point of the taxonomy, so both are first-class
    /// questions a view can ask rather than a `switch` each screen writes for itself.
    var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

extension LoadState: Equatable where Value: Equatable {}
extension LoadState: Hashable where Value: Hashable {}
