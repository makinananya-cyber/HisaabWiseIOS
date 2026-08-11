import Foundation

/// `GET /v1/content/articles/:id` — one article's body.
///
/// **Cacheable, and separate from Home's payload for that reason** (invariant 8, ADR-0020). The teasers are
/// small and sit inside the per-user screen response; a body is editorial content identical for every user, so
/// folding it in would make it per-user and throw the ETag away.
///
/// The structure is the design's own: a hero, then sections, each of which may carry paragraphs, a key-value
/// list, numbered steps, and a callout — then the article's sources. **Every block is optional and the order is
/// fixed**, which is how the design's `sections.forEach` reads: it draws `p`, then `list`, then `steps`, then
/// `callout`, and skips whichever are absent.
struct ArticleBody: Sendable, Hashable, Decodable, Identifiable {
    let id: String
    /// The full title — longer than the teaser's `short`.
    let title: String
    /// The standfirst under the title.
    let lede: String
    let sections: [Section]

    /// **Official sources only**, which is a compliance requirement rather than a nicety: this is education,
    /// not regulated financial advice, so every claim traces to u.ae, the Central Bank Rulebook, or similar.
    let sources: [Source]

    /// One section: a heading, and whichever blocks it has.
    struct Section: Sendable, Hashable, Decodable, Identifiable {
        /// The heading. Also the identity — sections have no ids in the design, and a heading is unique within
        /// an article. An index would be an identity that changes when a section is inserted above it.
        let heading: String
        /// Body paragraphs. **Emphasis is markdown**, not HTML — see ``HWMarkdown``.
        let paragraphs: [String]
        /// The design's `list` — a run of term-and-explanation pairs, which is what most of these articles are.
        let entries: [Entry]
        /// The design's `steps` — an ordered list, numbered by the view rather than by the content, so a step
        /// inserted in the middle does not need every following string edited.
        let steps: [String]
        /// A single highlighted paragraph, or `nil`.
        let callout: String?

        var id: String { heading }

        /// Absent blocks decode as empty rather than failing: a section with only a callout is a section the
        /// design has, and every block being required would make the payload carry four empty arrays to say so.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            heading = try container.decode(String.self, forKey: .heading)
            paragraphs = try container.decodeIfPresent([String].self, forKey: .paragraphs) ?? []
            entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
            steps = try container.decodeIfPresent([String].self, forKey: .steps) ?? []
            callout = try container.decodeIfPresent(String.self, forKey: .callout)
        }

        private enum CodingKeys: String, CodingKey {
            case heading, paragraphs, entries, steps, callout
        }
    }

    /// One row of a key-value list: the design's `{k, v}`.
    struct Entry: Sendable, Hashable, Decodable, Identifiable {
        let term: String
        let detail: String

        var id: String { term }
    }

    /// One source: a title and a link.
    struct Source: Sendable, Hashable, Decodable, Identifiable {
        let title: String
        let url: URL

        var id: URL { url }
    }
}

/// `GET /v1/content/tips` — the whole pool, cacheable.
///
/// **Home does not need it to paint.** The day's tip arrives inside the screen payload; this is fetched the first
/// time somebody presses **Show me another**, and cycling from then on is in memory (ADR-0016). Which is why it
/// lives beside `ArticleBody` rather than inside `HomeScreen`: both are content the screen *links to*, not content
/// the screen *is*.
struct TipList: Sendable, Hashable, Decodable {
    let tips: [Tip]

    /// One tip. The same shape the screen payload's selected tip has, minus the day it was chosen for — a pool
    /// entry belongs to no particular day.
    struct Tip: Sendable, Hashable, Decodable, Identifiable {
        let id: String
        /// `{c}` left verbatim, as the content rules require.
        let text: String
    }
}
