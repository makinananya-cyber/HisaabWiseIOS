import Observation

/// The value an unwritten screen loads: nothing, with a name.
///
/// ``BaseViewModel`` needs a `Value` and this is the smallest honest one. Declared beside its only user
/// rather than in `Models/` because the two are deleted together — a placeholder that outlives its
/// placeholder is how a temporary type becomes permanent.
struct NothingYet: Sendable, Equatable {}

/// The view model behind a tab whose screen has not been written yet — Expenses (#18), Learn (#19),
/// Reports (#21), Account (#23).
///
/// It exists because the shell is five tabs and four of the five screens are other people's tickets. What it
/// gives them is a real seam: each of those issues replaces one property's type on ``TabViewModels`` and
/// writes a `fetch()`, and nothing about the shell changes.
///
/// **It holds no client and makes no request, deliberately.** The obvious alternative — call the screen
/// endpoint ADR-0020 commits to — would put a fictional contract in the client: none of
/// `GET /v1/screens/{expenses,learn,reports,account}` exists on the backend yet, they are recorded in
/// `CONTEXT.md` as changes this repo *requires* elsewhere, and a request against an unwritten route renders
/// as "Something went wrong" on four of the five tabs. A screen that is not built is not a screen that is
/// broken, and the state the user sees should say the true thing.
///
/// So `fetch()` succeeds immediately and the screen draws ``UnwrittenTabRoot``'s one sentence. The path
/// through ``BaseViewModel/load()`` is the real one, which is what issue #5's criterion asks for: every tab
/// root renders its state through `StateView`.
@MainActor
@Observable
final class UnwrittenScreenViewModel: BaseViewModel {
    /// Not `private(set)`: ``BaseViewModel`` requires a settable `state`, and the trade-off is recorded
    /// there.
    var state: LoadState<NothingYet> = .loading

    func fetch() async throws -> NothingYet {
        NothingYet()
    }
}
