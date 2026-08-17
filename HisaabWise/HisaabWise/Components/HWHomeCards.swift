import SwiftUI

/// The design's `.tip` card — a lightbulb in a sun-coloured tile, the tip, and **Show me another**.
///
/// **It draws its own card, and that is the change that made it look like the design.** It used to be content
/// handed to an `HWCard`, which meant the one warm thing on Home was a white box like the two above it. The design
/// gives `.tip` its own surface — a `linear-gradient(140deg, --sun-soft, …)` inside a sun-coloured border, with a
/// blurred orb in the top corner and brown ink rather than galaxy — because a tip is not a figure: it is the one
/// card on the screen that is not about this month's money, and it is coloured to say so.
///
/// The text is **server content with markdown emphasis** (``HWMarkdown``), so it goes through
/// `Text(verbatim:)`-shaped rendering rather than a localised key: the words are the content's and the emphasis is
/// the author's. The `{c}` token has already been substituted by the caller from server-supplied currency
/// metadata, which is what keeps ADR-0003's spacing rule to one owner.
struct HWTipCard: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The tip, tokens resolved and emphasis as markdown.
    private let text: String
    private let onAnother: () -> Void

    init(text: String, onAnother: @escaping () -> Void) {
        self.text = text
        self.onAnother = onAnother
    }

    /// `.tip-ico{width:28px;height:28px}`, grown to the design's proportion at this type scale.
    private static let iconTile: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            top

            Text(HWMarkdown.attributed(text))
                // `.tip-txt{font-size:14px;line-height:1.6}` — the card's reason for existing, so it is a full
                // reading size rather than the caption the first pass drew it at.
                .font(.hw(.bodyLarge))
                .foregroundStyle(theme.palette.tip.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                // The tip changing is the one thing on this card that moves, and under Reduce Motion it is
                // replaced by arriving rather than by nothing (ADR-0012).
                .id(text)
                .transition(.opacity)

            another
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // `.tip{padding:17px 17px 16px}`
        .padding(17)
        .hwBox(
            fill: LinearGradient(
                colors: [theme.palette.tip.background, theme.palette.tip.backgroundEnd],
                // `140deg` — a shallow diagonal, so the warm end sits in the leading top corner where the icon is.
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            radius: .extraLarge,
            border: theme.palette.tip.border
        ) {
            orb
        }
        .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.standard), value: text)
        // One card, read as a card — the caption is its heading and the control at the foot is its own element.
        .accessibilityElement(children: .contain)
    }

    /// `.tip-top` — the glyph tile and the tracked caption beside it.
    private var top: some View {
        HStack(spacing: 9) {
            Image(systemName: "lightbulb.fill")
                .font(.hw(.body).weight(.bold))
                // White on the sun fill, as `.tip-ico{background:var(--sun);color:#fff}` has it.
                .foregroundStyle(theme.palette.brand.ink)
                .frame(width: Self.iconTile, height: Self.iconTile)
                .hwBox(fill: theme.palette.units.sun.base, radius: .small)
                .accessibilityHidden(true)

            // `.tip-cap{color:var(--sun-deep)}` — the eyebrow role, in the card's own accent rather than the
            // screen's. `hwEyebrow()` resolves to `accent.muted`, which on this warm wash is a blue-grey nobody
            // can read, so the size and tracking are taken and the colour is the card's.
            Text("home.tip.caption")
                .font(.hw(.micro).weight(.heavy))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(theme.palette.units.sun.deep)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// `.tip-next` — the reload glyph and **Show me another**, in the card's own accent.
    ///
    /// Not ``HWLink``: that is the accent-blue inline control, and on this wash it would be the only blue thing on
    /// a warm card. The glyph is the design's `<path d="M20 11.5A8 8 0 1 0 18 17"/>` — a circular arrow, which is
    /// what says the words cycle rather than navigate.
    private var another: some View {
        Button(action: onAnother) {
            HStack(spacing: 7) {
                // `arrow.clockwise` rather than a `.left`/`.right` variant: a rotation is not a reading direction,
                // so there is nothing here for RTL to mirror (ADR-0011).
                Image(systemName: "arrow.clockwise")
                    .font(.hw(.caption).weight(.heavy))

                Text("home.tip.another")
                    .font(.hw(.body).weight(.heavy))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(theme.palette.units.sun.deep)
            .frame(minHeight: HWTouchTarget.minimum, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        .accessibilityLabel(Text("home.tip.another"))
    }

    /// `.tip::after` — the blurred sun orb off the top-trailing corner. Static: the design drifts it over 9
    /// seconds, and see ``HWSurfaceWash`` for why an ambient loop on a background is not worth its redraw.
    private var orb: some View {
        RadialGradient(
            stops: [
                .init(color: theme.palette.units.sun.base.opacity(0.28), location: 0),
                .init(color: theme.palette.units.sun.base.opacity(0), location: 0.70),
            ],
            center: .center,
            startRadius: 0,
            endRadius: 75
        )
        .frame(width: 150, height: 150)
        .offset(x: 40, y: -80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .accessibilityHidden(true)
    }
}

/// The design's `.mini` — the streak, the XP line, and a way into the next lesson.
///
/// A **button**, as the design has it: the whole card is the affordance, so the tap target is the card rather than
/// the word "Continue" inside it.
///
/// **The one dark panel among the five in-app screens' cards**, and that is the design's decision rather than a
/// flourish: `background:linear-gradient(150deg,--galaxy,#16357C 60%,--planetary)` with `--milky` ink, a medium
/// elevation, and a `--sky` highlight in the corner. It drew as a white bordered card here, which put the learning
/// streak at the same visual weight as the article list beside it — and the streak is the thing on Home the app
/// most wants pressed. Note this is **not** the brand surface arriving on an in-app screen (ADR-0021): it is one
/// card painted dark, so its own ink roles come from `brand`, which is where light-on-galaxy ink lives.
struct HWStreakCard: View {
    @Environment(ThemeManager.self) private var theme

    /// Days, from the server — counted against the server-owned day boundary, so a device-clock change cannot
    /// extend it (invariant 6).
    private let streak: Int
    /// "120 XP · next up, Needs vs. Wants" — composed server-side, because it joins two figures and a title.
    private let summary: String
    /// The lesson **Continue** goes to.
    ///
    /// **Read by VoiceOver and not drawn**, which is a reversal: it used to be printed on the control as well as
    /// appearing inside `summary`. See the note at `.mini-go` in `body` for what that cost in the design's narrow
    /// column. The criterion that the next lesson be *shown* is met by `summary`, which the server composes with
    /// the title in it.
    private let nextLesson: String
    private let action: () -> Void

    init(streak: Int, summary: String, nextLesson: String, action: @escaping () -> Void) {
        self.streak = streak
        self.summary = summary
        self.nextLesson = nextLesson
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // `.mini-cap{color:var(--venus)}` — the eyebrow role read through the brand's ink, because the
                // surface's `accent.muted` is very nearly this card's own background.
                Text("home.learning.caption")
                    .hwEyebrow(.brand)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    // `.mini-flame svg{color:var(--sun)}` — the sun accent, not danger. A red flame on a navy
                    // card reads as a warning; the design's is amber, which reads as a flame.
                    Image(systemName: "flame.fill")
                        .font(.hw(.heading))
                        .foregroundStyle(theme.palette.units.sun.base)
                        .accessibilityHidden(true)

                    // `.mini-n{font-size:30px}` — Latin digits, unformatted (ADR-0011), and a count is not money.
                    Text(verbatim: "\(streak)")
                        .font(.hw(.display))
                        .foregroundStyle(theme.palette.brand.ink)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(verbatim: summary)
                    .font(.hw(.body))
                    .foregroundStyle(theme.palette.brand.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // `.mini-go` — **"Continue" and a chevron, and not the lesson's name.**
                //
                // The name used to be printed here too, on the argument that a control saying where it goes is
                // better than one that does not. In the design's two-up column that is 150pt wide it was the
                // same title twice — once inside `summary`, which the server composes as "120 XP · next up,
                // Needs vs. Wants", and again on the control — and the second copy hyphenated the word
                // "Continue" itself. So the name stays in the line above, where the server put it, and reaches
                // VoiceOver through the hint below, where a destination belongs.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("home.learning.continue")
                        .font(.hw(.body).weight(.heavy))
                        .fixedSize(horizontal: false, vertical: true)

                    // `chevron.forward` mirrors under Arabic; `.right` would point back the way the reader came.
                    Image(systemName: "chevron.forward")
                        .font(.hw(.caption).weight(.heavy))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // `.mini-go{color:var(--sky)}`
                .foregroundStyle(theme.palette.brand.inkAccent)
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .hwBox(
                // `linear-gradient(150deg, --galaxy, #16357C 60%, --planetary)` — the middle stop at 60%, which
                // is what stops it reading as a flat two-tone wash.
                fill: LinearGradient(
                    stops: [
                        .init(color: theme.palette.streak.start, location: 0),
                        .init(color: theme.palette.streak.middle, location: 0.60),
                        .init(color: theme.palette.streak.end, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                ),
                radius: .extraLarge,
                elevation: .medium
            ) {
                highlight
            }
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        // One control, read as "Learning, 4 day streak, 120 XP…, button". The streak is a *value* rather than part
        // of the label so that a change re-announces the number rather than the card's name (ADR-0012).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("home.learning.caption"))
        .accessibilityValue(Text("home.learning.accessibilityValue \(streakText) \(summary)"))
        // Where it goes, as a hint — the label names the card and the value carries the figures, so the
        // destination is the third thing and belongs in the third slot.
        .accessibilityHint(Text("home.learning.hint \(nextLesson)"))
    }

    /// The streak as a string, because every argument this app's copy takes is a `String` — a number would resolve
    /// to `%lld` and find nothing in the catalogue (`LocalisationTests`).
    private var streakText: String { "\(streak)" }

    /// `.mini::after` — the soft `--sky` glow off the top-trailing corner, which is what gives the panel depth
    /// rather than reading as a printed rectangle.
    private var highlight: some View {
        RadialGradient(
            stops: [
                .init(color: theme.palette.brand.inkAccent.opacity(0.30), location: 0),
                .init(color: theme.palette.brand.inkAccent.opacity(0), location: 0.70),
            ],
            center: .center,
            startRadius: 0,
            endRadius: 65
        )
        .frame(width: 130, height: 130)
        .offset(x: 40, y: -70)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .accessibilityHidden(true)
    }
}

/// One "Read more about" row — the design's `.read`.
///
/// The glyph and the tint arrive as a **name and a slot**, not as a path and a hex: the design hardcodes both per
/// article, and a colour that reaches a use site by name is what keeps the later dark-mode swap a swap (ADR-0001).
/// The row's **contents**, without a control around them.
///
/// Split out because Home draws these inside a `NavigationLink`, which supplies its own button: a `Button` nested
/// in a link is two controls for one row, and the first attempt at avoiding that turned the label's hit-testing
/// off — which made the rows completely untappable, exactly the way `HWDateField`'s placeholder was in #15. The
/// lesson recorded there is that a label must offer a hit region, so this one carries the `contentShape` and the
/// *link* is the control.
struct HWReadRowLabel: View {
    @Environment(ThemeManager.self) private var theme

    let title: String
    let systemImage: String
    /// Which of the five accent slots, `1...5`.
    let accent: Int

    var body: some View {
        // `.read{gap:9px;padding:9px 10px}` — the design's own spacing, kept rather than loosened. The row sits in
        // a column about 180pt wide, and every point spent on chrome is a point the title has to hyphenate for.
        HStack(spacing: 8) {
            // `.read-ico{width:26px;background:var(--card);color:var(--c)}` — the article's own colour on a white
            // tile, which is what distinguishes three rows that would otherwise be three chevrons.
            Image(systemName: systemImage)
                .font(.hw(.caption).weight(.semibold))
                .foregroundStyle(tint.deep)
                .frame(width: 26, height: 26)
                .hwBox(fill: theme.palette.surface.raised, radius: .small, border: tint.base.opacity(0.30))
                .accessibilityHidden(true)

            Text(verbatim: title)
                // `.read-t{font-weight:700}`, at a reading size rather than the design's 11.5px: these are the
                // three things on Home a reader is meant to want to open.
                .font(.hw(.body).weight(.bold))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.forward")
                .font(.hw(.micro).weight(.heavy))
                .foregroundStyle(theme.palette.accent.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(minHeight: HWTouchTarget.minimum)
        // `.read{background:var(--bg-2)}`, **with the hairline the design leaves implicit**. A meteor wash on a
        // white card is a two-per-cent difference in one channel: three rows drawn that way read as one block of
        // text with icons in it, which is what the outline fixes — each row is visibly its own control.
        .hwBox(
            fill: theme.palette.surface.backgroundSecondary,
            radius: .medium,
            border: theme.palette.surface.separatorStrong
        )
        // **The hit region.** Without it the row draws and cannot be pressed, whether the control around it is a
        // button or a link.
        .contentShape(.rect)
    }

    /// The five Learn unit accents, reused for the articles. A slot outside the range wraps: the number arrives
    /// from a payload, and a sixth article is a server change rather than a client crash.
    private var tint: HWPalette.UnitAccent {
        let accents = theme.palette.units.all
        guard !accents.isEmpty else { return theme.palette.units.sky }
        return accents[(max(accent, 1) - 1) % accents.count]
    }
}

/// One "Read more about" row as a **button**, for a caller that is not already a link.
struct HWReadRow: View {
    private let title: String
    private let systemImage: String
    private let accent: Int
    private let action: () -> Void

    init(title: String, systemImage: String, accent: Int, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HWReadRowLabel(title: title, systemImage: systemImage, accent: accent)
        }
        .buttonStyle(HWPressStyle.compact)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityHint(Text("home.reads.hint"))
    }
}

#if DEBUG
#Preview("The three cards, as Home arranges them") {
    ScrollView {
        VStack(spacing: 16) {
            HWTipCard(
                text: "To find 10% of a number, move the dot one step left. ₹6,400 becomes ₹640. Double it and "
                    + "there is your **20% savings target**."
            ) {}

            // The design's `.duo` — the dark streak panel on the leading side, the reading list beside it, at the
            // `1fr 1.15fr` ratio. Previewed together because the pair is the layout: each on its own says nothing
            // about whether the two read as siblings.
            HStack(alignment: .top, spacing: 12) {
                HWStreakCard(streak: 4, summary: "day streak · next up", nextLesson: "Needs vs. Wants") {}
                    .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    HWReadRow(title: "Scam awareness", systemImage: "checkmark.shield", accent: 3) {}
                    HWReadRow(title: "Remittances in the UAE", systemImage: "globe", accent: 2) {}
                    HWReadRow(title: "Debt management guidance", systemImage: "stairs", accent: 4) {}
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — every card grows and the pair stacks") {
    ScrollView {
        VStack(spacing: 16) {
            HWTipCard(text: "Keep **three months of rent, food and bills** saved for emergencies.") {}
            HWStreakCard(streak: 12, summary: "480 XP · 9 lessons done", nextLesson: "Borrowing and credit") {}
            HWReadRow(title: "Remittances in the UAE", systemImage: "globe", accent: 2) {}
        }
        .padding()
    }
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the glyphs lead on the right and the chevrons mirror") {
    VStack(spacing: 18) {
        HWTipCard(text: "احتفظ بمصروف **ثلاثة أشهر** للطوارئ.") {}
        HWStreakCard(streak: 4, summary: "120 XP", nextLesson: "الاحتياجات مقابل الرغبات") {}
        HWReadRow(title: "الوعي بالاحتيال", systemImage: "shield", accent: 3) {}
    }
    .padding()
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
