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
/// **This is education, not regulated financial advice** (the workspace's content rules), so the sources are part
/// of the article rather than a footnote: every claim traces to an official source, and the screen shows where.
struct ArticleView: BaseView {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.openURL) private var openURL

    let viewModel: ArticleViewModel

    /// The teaser's short title, shown while the body is still loading — so the screen the user tapped into is
    /// named before it has anything else on it.
    let title: String

    var stateCopy: StateCopy {
        StateCopy(empty: "article.empty")
    }

    @ViewBuilder
    func loadedContent(_ body: ArticleBody) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero(body)

                ForEach(body.sections) { section in
                    self.section(section)
                }

                if !body.sources.isEmpty {
                    sources(body.sources)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The pushed screen's own title, from the payload once it has one.
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// `.a-hero` — the full title and the standfirst.
    private func hero(_ body: ArticleBody) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: body.title)
                .font(.hw(.title))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: body.lede)
                .font(.hw(.bodyLarge))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// `.sec` — a heading and whichever blocks the section carries.
    private func section(_ section: ArticleBody.Section) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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

    /// One `{k, v}` row: the term, then what it means.
    private func entry(_ entry: ArticleBody.Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(HWMarkdown.attributed(entry.term))
                .font(.hw(.body).weight(.semibold))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(HWMarkdown.attributed(entry.detail))
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        // The term and its explanation are one thing to read.
        .accessibilityElement(children: .combine)
    }

    /// The design's `steps` — **numbered by the view**, so inserting a step in the middle does not mean editing
    /// every string after it. Latin digits, unformatted (ADR-0011).
    private func steps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: "\(index + 1)")
                        .font(.hw(.caption).weight(.bold))
                        .foregroundStyle(theme.palette.brand.ink)
                        .frame(width: 22, height: 22)
                        .hwBox(fill: theme.palette.accent.base, radius: .small)
                        // The number is read as part of the step below, not as a loose "1".
                        .accessibilityHidden(true)

                    Text(HWMarkdown.attributed(step))
                        .font(.hw(.body))
                        .foregroundStyle(theme.palette.surface.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    /// The design's `callout` — one highlighted paragraph.
    private func callout(_ text: String) -> some View {
        Text(HWMarkdown.attributed(text))
            .font(.hw(.body))
            .foregroundStyle(theme.palette.surface.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .hwBox(fill: theme.palette.accent.tint, radius: .medium, border: theme.palette.accent.soft)
    }

    /// The sources. **Official ones only**, which is why they are on the screen at all rather than in a footer:
    /// this is education, and the citation is part of the claim.
    private func sources(_ sources: [ArticleBody.Source]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("article.sources.caption")
                .hwEyebrow()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

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
                            .font(.hw(.caption))
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
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Article — every block the structure has") {
    NavigationStack { ArticleView(viewModel: .previewScams, title: "Scam awareness") }.hwTheme()
}

#Preview("Article — offline, with nothing cached") {
    NavigationStack { ArticleView(viewModel: .previewOffline, title: "Scam awareness") }.hwTheme()
}

#Preview("Article — Arabic, right to left") {
    NavigationStack { ArticleView(viewModel: .previewScams, title: "الوعي بالاحتيال") }
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("Article — AX5, where the reading matters most") {
    NavigationStack { ArticleView(viewModel: .previewScams, title: "Scam awareness") }
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
