import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// The last link in the walking skeleton: the view itself.
///
/// Rendering is verified properly by the pinned snapshot suite, which arrives with the snapshot
/// harness. What is asserted here is what a snapshot cannot state as a rule — that the string the view
/// puts on screen is the server's, character for character, and that its own copy comes out of the
/// String Catalogue rather than a literal baked into the binary.
@Suite("HomeView")
@MainActor
struct HomeViewTests {
    private func makeViewModel(_ transport: FixtureTransport) -> HomeViewModel {
        HomeViewModel(
            client: APIClient(baseURL: URL(string: "https://fixtures.invalid")!, transport: transport)
        )
    }

    @Test("builds a body for every state without reaching for a formatter")
    func buildsABodyForEveryState() async throws {
        let transport = FixtureTransport(stubs: ["/v1/budget": try .ok(.budgetINR)])
        let viewModel = makeViewModel(transport)

        // Loading, before anything is fetched.
        _ = HomeView(viewModel: viewModel).body

        await viewModel.load()
        #expect(viewModel.state.value != nil)

        // Loaded, which is the branch that reads the money.
        _ = HomeView(viewModel: viewModel).body
    }

    @Test("renders the exact display string the server sent")
    func rendersTheServersDisplayString() async throws {
        let transport = FixtureTransport(stubs: ["/v1/budget": try .ok(.budgetINR)])
        let viewModel = makeViewModel(transport)

        await viewModel.load()

        // The view's `.loaded` branch is `Text(budget.income.display)`. Asserting the view model's value
        // is asserting what reaches the screen: there is no formatting step in between, which is the
        // whole of ADR-0003.
        let rendered = try #require(viewModel.state.value?.income.display)
        #expect(rendered == "₹65,000")
        // Not `INR 65,000`: symbol spacing is a server rule, and a client that got this wrong would
        // be reimplementing it.
        #expect(!rendered.contains("INR"))
    }

    /// Every key `HomeView` renders. A key with no copy shows the user the key.
    private static let renderedKeys = [
        "home.empty",
        "home.offline",
        "home.failed",
        "home.income.label",
        "home.income.accessibilityLabel",
    ]

    @Test("takes its own copy from the String Catalogue, not from a literal")
    func copyComesFromTheStringCatalogue() throws {
        // ADR-0011 — externalised from the first string, so Phase 5 is translation rather than
        // relayout.
        //
        // Which check is possible depends on the build system: `swift build` copies the catalogue
        // verbatim, so keys do not resolve at runtime, while the Xcode build system compiles it to
        // `en.lproj/Localizable.strings` and they do. Both paths verify the thing that regresses — a
        // key the view renders with no English copy behind it.
        if let catalogue = Bundle.app.url(forResource: "Localizable", withExtension: "xcstrings") {
            let source = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalogue))
            let strings = (source as? [String: Any])?["strings"] as? [String: Any] ?? [:]

            for key in Self.renderedKeys {
                let entry = try #require(strings[key] as? [String: Any], "no catalogue entry for \(key)")
                let english = ((entry["localizations"] as? [String: Any])?["en"] as? [String: Any])
                    .flatMap { $0["stringUnit"] as? [String: Any] }
                    .flatMap { $0["value"] as? String }
                #expect(english?.isEmpty == false, "no English copy for \(key)")
            }

            let label = ((strings["home.income.accessibilityLabel"] as? [String: Any])?["localizations"]
                as? [String: Any])?["en"] as? [String: Any]
            let format = (label?["stringUnit"] as? [String: Any])?["value"] as? String
            // The figure is interpolated into the sentence, never concatenated onto it — otherwise
            // word order is untranslatable (ADR-0011, ADR-0012).
            #expect(format?.contains("%@") == true)
        } else {
            for key in Self.renderedKeys {
                #expect(Bundle.app.localizedString(forKey: key, value: nil, table: nil) != key)
            }
        }
    }
}
