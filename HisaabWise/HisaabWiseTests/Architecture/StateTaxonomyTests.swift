import Foundation
import Testing

/// The scans that keep ADR-0016's "one state taxonomy" true rather than aspirational.
///
/// All four rules held on the day issue #11 landed. None survives contact with eleven more screens on
/// good intentions alone: the failure mode is a file that adds "just one" inline `case .offline`, and
/// nothing about that compiles differently. So they are asserted, in the same spirit as `LayeringTests`
/// — weaker than a compiler, and the only enforcement there is.
@Suite("One state taxonomy")
struct StateTaxonomyTests {
    /// Where each single-owner rule lives. A scan naming a file that has been renamed would otherwise
    /// pass by reading nothing, so each is checked to actually contain what it owns.
    private static let owners = [
        "ViewModels/BaseViewModel.swift": "APIError",
        "DesignSystem/StateView.swift": "LoadState",
        "DesignSystem/ErrorCopy.swift": "ErrorCode",
    ]

    @Test("each single-owner file is the owner it claims to be")
    func ownersOwnSomething() throws {
        for (path, symbol) in Self.owners {
            let file = SourceTree.appSources.appending(path: path)
            #expect(
                try SourceTree.codeLines(of: file).contains { $0.contains(symbol) },
                "\(path) no longer mentions \(symbol) — the scan below now enforces nothing"
            )
        }
    }

    /// `StateView` is the only view that may switch on the taxonomy. A screen either goes through
    /// ``BaseView`` or the taxonomy has two owners again.
    @Test("no view or component switches on LoadState — screens go through BaseView")
    func viewsDoNotSwitchOnLoadState() throws {
        try SourceTree.expectAbsent(
            [
                // The type itself: a view holding one is a view about to switch on it.
                "LoadState",
                // And the switch, which can be written against `viewModel.state` without naming the type.
                "case .loading", "case .empty", "case .offline", "case .failed", "case .loaded",
            ],
            from: ["Views", "Components"],
            because: "the four empty-handed states are StateView's, reached through BaseView (ADR-0016, issue #11)"
        )
    }

    /// And nowhere else either. `Models` declares the enum and `DesignSystem` draws it; every other
    /// layer — plus the app root — is a place a second `switch` could grow unnoticed.
    @Test("nothing outside Models and DesignSystem switches on the taxonomy")
    func onlyTheDesignSystemSwitchesOnTheTaxonomy() throws {
        // `case .offline` is **not** in this list, and cannot be: `APIError` has a case of that name too,
        // and `BaseViewModel` and `APIError` both switch on *that* legitimately. Nothing is lost — a
        // `switch` over `LoadState` cannot be exhaustive without matching one of these four.
        let patterns = ["case .loading", "case .empty", "case .loaded", "case .failed"]
        // `ViewModels` *produces* states — `BaseViewModel.load()` assigns them — but never switches on
        // one, which is the distinction being drawn.
        let scanned = SourceTree.layers.filter { $0 != "Models" && $0 != "DesignSystem" }

        try SourceTree.expectAbsent(
            patterns,
            from: scanned,
            includingRoot: true,
            because: "StateView is the one switch over LoadState (ADR-0016, issue #11)"
        )
    }

    /// The mapping acceptance criterion, as a scan: `BaseViewModel.load()` is the **only** place an
    /// `APIError` becomes a `LoadState`. A second `catch APIError.offline` anywhere is a second chance to
    /// render a supported mode as a fault.
    /// **A read has exactly one owner; a form owns its own.** `BaseViewModel.load()` is the only place an error
    /// becomes a ``LoadState`` — that is the rule with teeth, because twelve screens share those four states. A
    /// *form* maps to field errors instead, which is not a `LoadState` and never could be: "offline" under a
    /// password box is not the same thing as an offline screen. Each form is one screen's own rules, so each names
    /// itself here, and another entry is a change somebody makes on purpose. `Networking` is skipped because that is where `APIError` is declared and thrown.
    @Test("a read maps errors in one place; each form maps its own")
    func errorMappingHasOneOwnerPerKind() throws {
        try expectAbsent(
            "APIError",
            outside: [
                "ViewModels/BaseViewModel.swift",
                "ViewModels/SignInViewModel.swift",
                "ViewModels/RegistrationViewModel.swift",
            ],
            skippingLayers: ["Networking"],
            because: "a read becomes a LoadState in BaseViewModel.load(); a form becomes field errors in SignInViewModel"
        )
    }

    /// And the other half of ADR-0016: an error *code* becomes copy in one place. A screen never sees a
    /// code at all — if one reaches a view, the next commit renders it.
    @Test("an error code becomes copy in exactly one place")
    func errorCopyHasOneOwner() throws {
        // `Models` declares `ErrorCode` and `ViewModels` may legitimately branch on one — Expenses will,
        // to offer re-filing on `MONTH_CLOSED`. Turning a code into a *sentence* is the single-owner part.
        try expectAbsent(
            "ErrorCode",
            outside: ["DesignSystem/ErrorCopy.swift"],
            skippingLayers: ["Models", "ViewModels", "Networking"],
            because: "ErrorCopy is the one place a code becomes copy, and no screen ever sees one (ADR-0016)"
        )
    }

    /// Asserts `symbol` appears in no source file except `owner`, skipping whole layers where it is
    /// legitimately at home. Scans the app root too — a rule that stopped at the layer folders would
    /// leave `HisaabWiseApp.swift` and `AppEnvironment.swift` free to break it.
    private func expectAbsent(
        _ symbol: String,
        outside owners: [String],
        skippingLayers skipped: [String],
        because reason: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let ownerFiles = Set(owners.map { SourceTree.appSources.appending(path: $0).lastPathComponent })
        var files = try SourceTree.rootSwiftFiles()
        for layer in SourceTree.layers where !skipped.contains(layer) {
            files += try SourceTree.swiftFiles(in: layer)
        }

        var scanned = 0
        for file in files where !ownerFiles.contains(file.lastPathComponent) {
            scanned += 1
            let offender = try SourceTree.codeLines(of: file).first { $0.contains(symbol) }
            #expect(
                offender == nil,
                """
                \(file.lastPathComponent) references \(symbol) — \(reason)
                \(offender ?? "")
                """,
                sourceLocation: sourceLocation
            )
        }

        // A scan that read nothing would pass silently.
        #expect(scanned > 0, sourceLocation: sourceLocation)
    }
}
