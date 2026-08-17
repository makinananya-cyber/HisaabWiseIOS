import SwiftUI

/// One article, converted from the design's `page-read` — the other half of a "Read more about" row.
///
/// **A `BaseView` over cacheable content.** Every other screen reads a per-user endpoint; this reads an ETag'd
/// article body through the content store, so a second visit costs a `304` and an offline visit shows the copy
/// already on disk (ADR-0009, ADR-0020). The four states are the shared ones, unchanged.
///
/// **Every block is drawn by the same rules the design draws them by**, and the order is fixed: paragraphs, then
/// the key-value list, then numbered steps, then the callout. A section that has only a callout is a section the
/// design has, so each block is skipped when absent rather than reserved.
///
/// **The article is tinted, and that is the change that made it read as an article.** It was a plain column —
/// a title, a standfirst, headings, and indented paragraphs, all in two inks on one ground — which is a specification
/// document rather than something anybody reads for pleasure. The design gives each article its own accent and uses
/// it in five places: a full-bleed `.a-hero` in the accent gradient, the dot on every `.sec-li`, the number on every
/// step, the border and wash of the `.callout`, and the glyph tile in the hero. The accent arrives as a **slot**
/// from the teaser that opened it — the same number the row on Home was drawn with, so a green row opens a green
/// article — rather than as a colour in the payload (ADR-0001).
///
/// **This is education, not regulated financial advice** (the workspace's content rules), so the sources are part
/// of the article rather than a footnote: every claim traces to an official source, and the screen shows where.
struct ArticleView: BaseView {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.openURL) private var openURL

    let viewModel: ArticleViewModel

    /// The teaser's short title, shown while the body is still loading — so the screen the user tapped into is
    /// named before it has anything else on it.
    let title: String

    /// The glyph the teaser was drawn with, for the hero's tile. An SF Symbol name rather than
    /// `HomeScreen.Icon`, because the mapping from the payload's closed set to a symbol is `HomeView`'s and
    /// already written there — a second copy here is the second table that gets one wrong (ADR-0001).
    let systemImage: String

    /// Which of the five accent slots, `1...5` — the teaser's own, so the row and the article it opens agree.
    let accent: Int

    init(viewModel: ArticleViewModel, title: String, systemImage: String = "lightbulb", accent: Int = 4) {
        self.viewModel = viewModel
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
    }

    var stateCopy: StateCopy {
        StateCopy(empty: "article.empty")
    }

    /// The article's accent, resolved once per render and handed to every block that needs it.
    ///
    /// The five Learn unit accents, reused for the articles — as ``HWReadRowLabel`` resolves them, by the same
    /// wrapping rule: a slot outside the range wraps, because the number arrives from a payload and a sixth
    /// article is a server change rather than a client crash.
    private var tint: HWPalette.UnitAccent {
        let accents = theme.palette.units.all
        guard !accents.isEmpty else { return theme.palette.units.sky }
        return accents[(max(accent, 1) - 1) % accents.count]
    }

    @ViewBuilder
    func loadedContent(_ body: ArticleBody) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero(body)

                ForEach(body.sections) { section in
                    self.section(section)
                }

                if !body.sources.isEmpty {
                    sources(body.sources)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The pushed screen's own title, from the payload once it has one.
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - The hero

    /// `.a-hero` — the accent panel that opens the article: a glyph tile, the full title, and the standfirst.
    ///
    /// Full-bleed colour with `--milky` ink, so the ink roles come from `brand` rather than `surface` — the same
    /// borrowing ``HWStreakCard`` does, and for the same reason: one card painted dark is not the brand appearance
    /// arriving on an in-app screen (ADR-0021), it is a card that needs light ink.
    private func hero(_ body: ArticleBody) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // `.a-hero-ico{background:rgba(255,255,255,.22);border:1px solid rgba(255,255,255,.3)}`
            Image(systemName: systemImage)
                .font(.hw(.subheading))
                .foregroundStyle(theme.palette.brand.ink)
                .frame(width: 46, height: 46)
                .hwBox(
                    fill: theme.palette.brand.ink.opacity(0.22),
                    radius: .medium,
                    border: theme.palette.brand.ink.opacity(0.30)
                )
                .padding(.bottom, 4)
                .accessibilityHidden(true)

            Text(verbatim: body.title)
                .font(.hw(.heading))
                .foregroundStyle(theme.palette.brand.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: body.lede)
                .font(.hw(.body))
                .foregroundStyle(theme.palette.brand.ink.opacity(0.92))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .hwBox(
            // `linear-gradient(145deg, var(--ac), var(--ac-2))` — the accent into its own deep, which is the
            // pair the palette already holds for every slot.
            fill: LinearGradient(
                colors: [tint.base, tint.deep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            radius: .extraLarge,
            elevation: .medium
        ) {
            highlight
        }
        // The title and the standfirst are one thing to read, and the whole panel is the article's heading.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// `.a-hero::after` — the soft white glow off the top-trailing corner.
    private var highlight: some View {
        RadialGradient(
            stops: [
                .init(color: theme.palette.brand.ink.opacity(0.28), location: 0),
                .init(color: theme.palette.brand.ink.opacity(0), location: 0.70),
            ],
            center: .center,
            startRadius: 0,
            endRadius: 85
        )
        .frame(width: 170, height: 170)
        .offset(x: 46, y: -92)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .accessibilityHidden(true)
    }

    // MARK: - A section

    /// `.sec` — a heading and whichever blocks the section carries.
    private func section(_ section: ArticleBody.Section) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(verbatim: section.heading)
                .font(.hw(.subheading))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                // A real heading, so VoiceOver's heading rotor moves through the article as an article.
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(HWMarkdown.attributed(paragraph))
                    .font(.hw(.body))
                    .foregroundStyle(theme.palette.surface.inkSecondary)
                    // `line-height:1.65` — the reading measure, and the one number on this screen that is worth
                    // transcribing exactly. Long-form copy set solid is copy nobody finishes.
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(section.entries) { entry in
                self.entry(entry)
            }

            if !section.steps.isEmpty {
                steps(section.steps)
            }

            if let callout = section.callout {
                self.callout(callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One `{k, v}` row — the design's `.sec-li`: **a card with an accent dot**, the term, and what it means.
    ///
    /// It was an indented paragraph pair, which turned "the five signs of a scam" into one wall of text with some
    /// bold words in it. A card each is what makes five signs read as five things.
    private func entry(_ entry: ArticleBody.Entry) -> some View {
        HStack(alignment: .top, spacing: 11) {
            // `.sec-li .dot{width:7px;background:var(--ac);margin-top:6px}` — aligned to the term's first line
            // rather than centred, so a two-line term does not push it into the middle of the card.
            Circle()
                .fill(tint.base)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(HWMarkdown.attributed(entry.term))
                    .font(.hw(.body).weight(.heavy))
                    .foregroundStyle(theme.palette.surface.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(HWMarkdown.attributed(entry.detail))
                    .font(.hw(.body))
                    .foregroundStyle(theme.palette.surface.inkSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .hwBox(
            fill: theme.palette.surface.raised,
            radius: .medium,
            border: theme.palette.surface.separator,
            elevation: .small
        )
        // The term and its explanation are one thing to read.
        .accessibilityElement(children: .combine)
    }

    /// The design's `steps` — **numbered by the view**, so inserting a step in the middle does not mean editing
    /// every string after it. Latin digits, unformatted (ADR-0011).
    private func steps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 11) {
                    // `.steps li::before{background:var(--ac-soft);color:var(--ac-2)}` — the accent's wash with
                    // its own deep ink, which is the pair the palette holds for exactly this.
                    Text(verbatim: "\(index + 1)")
                        .font(.hw(.caption).weight(.heavy))
                        .foregroundStyle(tint.deep)
                        .frame(width: 24, height: 24)
                        .hwBox(fill: tint.soft, radius: .small)
                        // The number is read as part of the step below, not as a loose "1".
                        .accessibilityHidden(true)

                    Text(HWMarkdown.attributed(step))
                        .font(.hw(.body))
                        .foregroundStyle(theme.palette.surface.inkSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .hwBox(
                    fill: theme.palette.surface.raised,
                    radius: .medium,
                    border: theme.palette.surface.separator,
                    elevation: .small
                )
                // "Step 2 of 4" then the words, so a listener knows where they are in the list.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text("article.step.accessibilityLabel \("\(index + 1)") \("\(steps.count)")")
                )
                .accessibilityValue(Text(verbatim: step))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The design's `callout` — one highlighted paragraph, in **the article's own accent** rather than the app's.
    ///
    /// It was drawn in `accent.tint`, the blue wash, on every article: a red article with one blue box in it. The
    /// design sets `--ac-soft` and `--ac-line` per article and uses them here, which is what makes the callout read
    /// as this article raising its voice rather than as a system notice.
    private func callout(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.circle")
                .font(.hw(.bodyLarge))
                .foregroundStyle(tint.deep)
                .accessibilityHidden(true)

            Text(HWMarkdown.attributed(text))
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .hwBox(fill: tint.soft, radius: .large, border: tint.base.opacity(0.28))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sources

    /// The sources — the design's `.srcs`, a bordered meteor panel at the foot rather than a loose list.
    ///
    /// **Official ones only**, which is why they are on the screen at all rather than in a footer: this is
    /// education, and the citation is part of the claim. The panel is what says the article has ended and where it
    /// came from, in that order.
    private func sources(_ sources: [ArticleBody.Source]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("article.sources.caption")
                .hwEyebrow()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 2)

            ForEach(sources) { source in
                Button {
                    openURL(source.url)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "link")
                            .font(.hw(.caption))
                            .foregroundStyle(theme.palette.accent.base)
                            .accessibilityHidden(true)

                        Text(verbatim: source.title)
                            .font(.hw(.body).weight(.medium))
                            .foregroundStyle(theme.palette.accent.base)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: HWTouchTarget.minimum)
                    .contentShape(.rect)
                }
                .buttonStyle(HWPressStyle.compact)
                .accessibilityLabel(Text(verbatim: source.title))
                .accessibilityHint(Text("article.sources.hint"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .hwBox(
            fill: theme.palette.surface.backgroundSecondary,
            radius: .large,
            border: theme.palette.surface.separator
        )
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Article — every block the structure has") {
    NavigationStack {
        ArticleView(
            viewModel: .previewScams,
            title: "Scam awareness",
            systemImage: "checkmark.shield",
            accent: 3
        )
    }
    .hwTheme()
}

/// A second accent, so the five places the tint reaches can be seen changing together.
#Preview("Article — a different accent tints all five places") {
    NavigationStack {
        ArticleView(viewModel: .previewScams, title: "Remittances in the UAE", systemImage: "globe", accent: 2)
    }
    .hwTheme()
}

#Preview("Article — offline, with nothing cached") {
    NavigationStack { ArticleView(viewModel: .previewOffline, title: "Scam awareness") }.hwTheme()
}

#Preview("Article — Arabic, right to left") {
    NavigationStack {
        ArticleView(viewModel: .previewScams, title: "الوعي بالاحتيال", systemImage: "checkmark.shield", accent: 3)
    }
    .hwTheme()
    .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("Article — AX5, where the reading matters most") {
    NavigationStack {
        ArticleView(
            viewModel: .previewScams,
            title: "Scam awareness",
            systemImage: "checkmark.shield",
            accent: 3
        )
    }
    .hwTheme()
    .dynamicTypeSize(.accessibility5)
}
#endif
