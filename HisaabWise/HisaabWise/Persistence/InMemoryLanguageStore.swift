/// The language choice with no device footprint.
///
/// The counterpart of ``InMemoryTokenStore``, and here for one of its two reasons rather than both: not
/// because a user asked for nothing to be kept — a language preference has no "keep me signed in" — but
/// so that a test can exercise the persistence path without writing to the preferences of the machine the
/// suite runs on. It is also what a preview uses, where writing a preference from the canvas would leak
/// into the next launch of the simulator.
@MainActor
final class InMemoryLanguageStore: LanguageStore {
    private(set) var language: AppLanguage?

    /// - Parameter language: a choice already made, which is otherwise only reachable by making one.
    init(language: AppLanguage? = nil) {
        self.language = language
    }

    func save(_ language: AppLanguage) {
        self.language = language
    }
}
