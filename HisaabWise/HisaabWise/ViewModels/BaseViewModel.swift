import Observation

/// The contract every screen's view model conforms to: one request, one ``LoadState``, no mapping of
/// its own.
///
/// A **protocol, not a base class**, for two reasons. `@Observable` is a macro that has to sit on the
/// concrete type to generate anything useful, and a subclass of an `@Observable` base class does not
/// get the observation its stored properties need. And a view model composes — Learn's lesson player
/// will hold a session as well as a fetch — where inheritance would force it to be one thing.
///
/// What conforming buys a screen is the whole of ADR-0016: the `.loading` → `.loaded` / `.empty` /
/// `.offline` / `.failed` mapping happens in ``load()`` and nowhere else. Before this existed, each
/// screen wrote its own `catch`, which is twelve chances to render `APIError.offline` as a fault.
///
/// **The trade-off this shape carries, deliberately unsolved.** The requirement is
/// `var state { get set }`, so a conformance *cannot* declare `private(set) var state` — the setter
/// has to be as visible as the protocol. Confining mutation to ``load()`` is therefore a convention
/// here rather than something the compiler guarantees. Making it a guarantee would mean a base class
/// (and losing `@Observable`) or a wrapper object per screen, and neither is worth it for a rule that
/// has one enforcement point and reads plainly in every conformance.
@MainActor
protocol BaseViewModel: AnyObject, Observable {
    /// What the screen renders when it has data. `Equatable` so a test can assert on a whole state
    /// rather than picking through it, and `Sendable` because the value crosses the client's actor
    /// boundary to get here.
    associatedtype Value: Sendable & Equatable

    /// The screen's presentation state. Read by ``BaseView``; written by ``load()``.
    var state: LoadState<Value> { get set }

    /// The one request this screen's data comes from.
    ///
    /// One per screen by decision, not by coincidence: reads are screen-shaped (ADR-0020), so a
    /// screen that needs two requests is a screen whose endpoint has not been written yet.
    func fetch() async throws -> Value

    /// Whether a successful response should render as ``LoadState/empty``.
    ///
    /// Defaulted to `false`, which is right for every screen whose payload is a set of figures. A
    /// screen with a list on it overrides it — `.loaded([])` draws an empty list where `.empty` draws
    /// the copy that tells the user why.
    func isEmpty(_ value: Value) -> Bool
}

extension BaseViewModel {
    func isEmpty(_ value: Value) -> Bool { false }

    /// Fetches, and maps the outcome to a ``LoadState``.
    ///
    /// **This is the only place in the app that turns an `APIError` into a ``LoadState``.** The two
    /// rules ADR-0016 attaches to the taxonomy are enforced here, once:
    ///
    /// - `APIError.offline` becomes ``LoadState/offline`` and never ``LoadState/failed(_:)``. Offline
    ///   is a supported mode, not a fault (ADR-0004 as amended by ADR-0019: the write path is gone,
    ///   the read state is not).
    /// - ``LoadState/failed(_:)`` carries an ``ErrorCode`` and never the server's prose, which the
    ///   client does not decode in the first place.
    ///
    /// - Throws: `CancellationError`, and only that. A user navigating away from a screen mid-request
    ///   is not offline and has not hit an error, so the abandoned load reports nothing and leaves
    ///   `state` where it found it. Every other failure is a state, not a throw.
    func load() async throws {
        state = .loading
        do {
            let value = try await fetch()
            state = isEmpty(value) ? .empty : .loaded(value)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A transport that reports cancellation as an ordinary failure — `URLSession` raises
            // `URLError.cancelled`, indistinguishable to the client from a dropped connection — must
            // not be allowed to render as offline either.
            if Task.isCancelled { throw CancellationError() }
            state = Self.failureState(for: error)
        }
    }

    /// The mapping itself, kept separate from the sequencing above so that the one place it lives is
    /// a place worth reading.
    private static func failureState(for error: any Error) -> LoadState<Value> {
        guard let apiError = error as? APIError else {
            // Not a network failure at all — a decoding helper, a programmer error, a layer that does
            // not exist yet. It is a fault, and it renders as one, without a fabricated code.
            return .failed(.unknown)
        }
        switch apiError {
        case .offline:
            return .offline
        case .server, .malformedResponse:
            // `APIError.offline` is the only case with no code, and it is handled above — so the
            // fallback here is a belt, not a route anything takes.
            return .failed(apiError.errorCode ?? .unknown)
        }
    }
}
