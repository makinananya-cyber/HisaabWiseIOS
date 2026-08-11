/// The five tabs, in the order the tab bar shows them.
///
/// Product Spec §3 — Home · Expenses · Learn · Reports · Account, **all reachable from all**, with log out
/// as the only way out of them. That is what a `TabView` is, so the interesting part of this type is not the
/// navigation: it is that the set is closed and ordered in one place, so a screen, a view model, and a tab
/// item cannot disagree about how many there are.
///
/// **It carries identity and order, and no words or glyphs.** Those are in `Views/AppShell.swift`, as an
/// extension: copy belongs in the presentation layer, where the localisation scans look for it, and a
/// `Models` type holding a String Catalogue key would read as an orphaned entry to
/// `LocalisationTests.noCatalogueEntryIsOrphaned`.
///
/// `Hashable` because that is what a `TabView` selects on, and `CaseIterable` because the tab bar, the tests,
/// and the localisation scan all want to walk the set rather than re-list it. **No raw values**: nothing needs a
/// string for a tab, and one would invite being used as a URL path — a screen's endpoint is its view model's
/// business (ADR-0020).
enum AppTab: CaseIterable, Hashable, Sendable {
    case home
    case expenses
    case learn
    case reports
    case account
}
