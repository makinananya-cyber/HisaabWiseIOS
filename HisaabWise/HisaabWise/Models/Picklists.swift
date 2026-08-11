import Foundation

/// `GET /v1/content/picklists` — the two lists the Expenses entry form picks from.
///
/// **Server-served and cacheable** (ADR-0009, invariant 8): the same 42 options for everybody, so they are
/// stored with an ETag rather than compiled into the binary. The design carries them as two JavaScript
/// constants, which is what "content is server-served and versioned, never compiled into the app" exists to
/// prevent — a new transport mode would otherwise be an App Store release.
///
/// The counts are the acceptance test the workspace's content rules set: **22** transport modes and **20**
/// "Other" types. `PicklistTests` asserts them exactly rather than as a range.
struct Picklists: Sendable, Hashable, Decodable {
    let transport: [Option]
    let other: [Option]

    /// One option in a pick list.
    struct Option: Sendable, Hashable, Decodable, Identifiable {
        /// What comes back on selection, and **what is sent to the server** rather than the name.
        ///
        /// The same rule §4.3 **[FIX]** applies to a security question: the id is the identity. Sending the
        /// displayed name would mean an Arabic-reading user filing an entry labelled in Arabic and an
        /// English-reading one filing the same entry labelled in English, with nothing to reconcile them —
        /// the server resolves the id into a name in whatever language the reader asks for.
        let id: String

        /// `.opt-name` — what the row says. Server content, in the user's language.
        let name: String

        /// Whether choosing this option asks the user to type what it actually was.
        ///
        /// **A flag, not a name match.** The design tests `/something else/i.test(val)` against the selected
        /// option's English text, which stops working the moment the list is translated — the one option whose
        /// behaviour differs would silently become an ordinary option for every Arabic reader. Recorded as a
        /// [FIX] in ADR-0033.
        let opensFreeText: Bool

        private enum CodingKeys: String, CodingKey {
            case id, name, opensFreeText
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            // Absent for the 41 ordinary options, so the flag is written where it is true and nowhere else.
            opensFreeText = try container.decodeIfPresent(Bool.self, forKey: .opensFreeText) ?? false
        }
    }

    /// The options for one list.
    func options(for picklist: ExpensesScreen.Picklist) -> [Option] {
        switch picklist {
        case .transport: transport
        case .other: other
        }
    }
}
