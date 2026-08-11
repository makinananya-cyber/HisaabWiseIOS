import Foundation

/// Server content with **markdown emphasis**, as something a `Text` can draw.
///
/// The design writes emphasis as HTML — `<b>` in tips, `<b>` and `<i>` inside article paragraphs, steps, and
/// list entries. HTML cannot reach a `Text`, so the extraction into `content/*.json` converts it to markdown and
/// this is what renders it. One helper, two callers: the tip card and the article body.
///
/// **Why not strip the emphasis.** It is not decoration. "No bank will *ever* ask for your OTP" and "your
/// end-of-service payout is worked out from your **basic salary only**" both put the weight on the word that
/// changes the meaning, and a flattened sentence loses the thing the sentence is for.
///
/// **Why not `Text(someLocalizedKey)`.** Markdown in a `Text` comes free for *app copy*, because a
/// `LocalizedStringKey` is parsed as markdown. This is **server content** and must go through `Text(verbatim:)`,
/// which is not — so the parse is explicit here.
///
/// `AttributedString(markdown:)` is locale-independent: it reads `**` and `*`, not a language. Failure falls back
/// to the plain string rather than throwing, because an article with a stray asterisk in it should read as an
/// article with a stray asterisk in it.
enum HWMarkdown {
    /// The inline-only options: no block parsing, so a line starting with `#` in editorial copy stays a `#`
    /// rather than silently becoming a heading.
    private static let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace
    )

    /// `text` with its `**bold**` and `*italic*` runs resolved.
    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
