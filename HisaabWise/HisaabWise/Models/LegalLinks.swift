import Foundation

/// The two hosted pages the app has to be able to link to: Terms of Use and the Privacy Policy.
///
/// A pair rather than two loose `URL`s because they always travel together — the consent checkbox on registration
/// needs both (#15), and so will the Account screen (#17) — and because a function taking two same-typed URLs is a
/// function whose arguments can be swapped silently.
///
/// **Read from build configuration, never hardcoded** (ADR-0010, Rule 7). `AppConfig` parses them; this is the
/// value it parses into, which is why the type lives here and not beside the parsing: a model knows what a legal
/// link *is*, not where the build kept it.
struct LegalLinks: Sendable, Hashable {
    let terms: URL
    let privacy: URL
}
