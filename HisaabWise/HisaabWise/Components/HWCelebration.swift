import SwiftUI

/// The design's `.done-badge` — the 110pt tick that opens the celebration screen.
///
/// **It is also the replacement for the confetti** (ADR-0012): a motion-sensitive reader gets no falling paper, and
/// what is left has to still read as a celebration rather than as a screen that failed to load one. So the badge is
/// permanent and only its *arrival* is conditional — it appears in place rather than spinning in.
struct HWDoneBadge: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasArrived = false

    /// `.done-badge{width:110px}`.
    private static let diameter: CGFloat = 110

    var body: some View {
        Image(systemName: "checkmark")
            // The largest step in the scale rather than the design's 52px, because a glyph pinned in points is a
            // glyph that does not grow (ADR-0012) — and the circle around it is drawn from the same design.
            .font(.hw(.display).weight(.heavy))
            .foregroundStyle(theme.palette.brand.ink)
            .frame(width: Self.diameter, height: Self.diameter)
            .hwBox(
                fill: LinearGradient(
                    colors: [theme.palette.units.sun.base, theme.palette.units.sun.deep],
                    // `.topLeading`/`.bottomTrailing` rather than the design's 150°, because two `UnitPoint`s
                    // mirror with the layout and a degree does not (ADR-0011).
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                radius: .pill,
                elevation: .medium
            )
            // `badgeIn{from{transform:scale(.3) rotate(-25deg)}}` — the overshoot is the arrival, and under Reduce
            // Motion the badge has simply already arrived, which is what the design's own reduced-motion block does.
            .scaleEffect(reduceMotion || hasArrived ? 1 : 0.4)
            .animation(reduceMotion ? nil : HWMotion.easeBack.animation(.slow), value: hasArrived)
            .onAppear { hasArrived = true }
            // The screen says what was achieved in words; a decorative tick would announce "checkmark".
            .accessibilityHidden(true)
    }
}

/// The design's `.dstat` — one of the three tiles under the headline: XP earned, accuracy, day streak.
///
/// **The figure arrives as a string and this component never spells one.** A four-digit XP total has a thousands
/// separator the client owns no formatter for, and "+50" carries a sign whose side of the number is a language's
/// decision (ADR-0003, ADR-0033). The caption is app copy; the value is the server's.
struct HWCompletionStat: View {
    @Environment(ThemeManager.self) private var theme

    /// Which of the design's three tints the tile takes.
    ///
    /// A component-owned enum rather than a colour, for ``HWStatChip/Tone``'s reason: the caller says what the
    /// figure *is* and the component says what that looks like.
    enum Tone: Sendable, Equatable, CaseIterable {
        /// `.dstat.xp b{color:var(--planetary)}`.
        case experience
        /// `.dstat.acc b{color:var(--mint-deep)}`.
        case accuracy
        /// `.dstat.st b{color:var(--sun-deep)}`.
        case streak
    }

    private let tone: Tone
    /// "+50" · "75%" · "5" — server-formatted, and the only thing drawn.
    private let value: String
    /// "XP EARNED" · "ACCURACY" · "DAY STREAK".
    private let caption: LocalizedStringResource
    /// The whole reading — "50 experience points earned". Server-composed, because it is a count with a plural in
    /// it (ADR-0011).
    private let accessibilityLabel: String

    init(tone: Tone, value: String, caption: LocalizedStringResource, accessibilityLabel: String) {
        self.tone = tone
        self.value = value
        self.caption = caption
        self.accessibilityLabel = accessibilityLabel
    }

    private var ink: Color {
        switch tone {
        case .experience: theme.palette.accent.base
        case .accuracy: theme.palette.units.mint.deep
        case .streak: theme.palette.units.sun.deep
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(verbatim: value)
                .font(.hw(.heading))
                .foregroundStyle(ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            Text(caption)
                .hwEyebrow()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 13)
        .hwBox(
            fill: theme.palette.surface.raised,
            radius: .large,
            border: theme.palette.surface.separator,
            elevation: .small
        )
        // One element carrying the figure and what it is of — three of these in a row is three facts, not six.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }
}

/// The design's `.done-stats` — the three tiles, sharing the width **until they cannot**.
///
/// **Reading the size to choose a layout is not clamping** (ADR-0012), and this is the third caller of that
/// distinction after `HWSpendSummary` and Home's two-up grid: a row of three at accessibility sizes leaves each tile
/// about 100pt, which breaks `+1,500` across three lines and `ACCURACY` across two. Above the threshold the row is a
/// column and each tile has the whole width; below it, a `Grid` rather than an `HStack`, so all three take the height
/// of the tallest — "XP earned" wraps a word sooner than "Accuracy" and a row would leave three boxes of three
/// heights.
struct HWCompletionStats<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var size

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if size.isAccessibilitySize {
            VStack(spacing: 10) { content }
                .frame(maxWidth: .infinity)
        } else {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow { content }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// The design's `.week` — seven days, each lit if something was finished that day.
///
/// **Replaced rather than shrunk above the accessibility threshold** (ADR-0012), and it is the fourth of the four
/// visualisations that ADR names. Seven 26pt circles with two-letter captions under them have nowhere to grow; the
/// replacement is the same seven days as **rows**, which is text and scales the whole way to AX5. The rows are also
/// installed as the strip's `accessibilityRepresentation` below the threshold, so a VoiceOver user reads the list at
/// every size.
///
/// **Every label and every state is the server's** (invariant 6). The design builds the strip from
/// `new Date().getDay()` and a subtraction over the streak, which puts the reader's week on the device clock — so
/// moving the clock moves the strip, and with it the story the streak tells.
struct HWWeekStrip: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One day, as the payload sends it.
    struct Day: Sendable, Equatable {
        /// "Su" — the short label, in the reader's language.
        let label: String
        let isComplete: Bool
        let isToday: Bool
        /// "Sunday, lesson finished" — the whole reading, composed server-side.
        let accessibilityLabel: String
    }

    private let days: [Day]

    init(days: [Day]) {
        self.days = days
    }

    /// `.wd i{width:26px}`.
    private static let markSize: CGFloat = 26

    var body: some View {
        strip
            // **`describesItself` is `true`, and that is not the default for a hand-built shape.** Each circle here is
            // its own accessibility element carrying the server's whole sentence for that day, so installing the rows
            // as the strip's representation below the threshold would *discard* seven labels that exist — the mistake
            // ADR-0025 records the donut making in reverse. Above the threshold the rows are what is drawn, which is
            // where they earn their keep.
            .hwVisualisation(describesItself: true) { rows }
    }

    /// The strip itself: a caption over a filled or empty circle, seven times.
    private var strip: some View {
        HStack(spacing: 7) {
            // Keyed by position, because a short label is not unique in every language — two of the seven can read
            // the same, and a duplicate identity draws one of them (the reason `ArticleView` keys its steps this
            // way).
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 5) {
                    Text(verbatim: day.label)
                        .font(.hw(.micro).weight(.heavy))
                        .foregroundStyle(day.isComplete ? theme.palette.units.sun.deep : theme.palette.surface.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Image(systemName: "checkmark")
                        .font(.hw(.micro).weight(.heavy))
                        .foregroundStyle(theme.palette.brand.ink)
                        .opacity(day.isComplete ? 1 : 0)
                        .frame(width: Self.markSize, height: Self.markSize)
                        .hwBox(
                            fill: day.isComplete ? theme.palette.units.sun.base : theme.palette.feedback.emptyTrack,
                            radius: .pill,
                            // Today is outlined as well as filled, so "which day is this" survives a reader who
                            // cannot tell the design's bump animation from the six other circles.
                            border: day.isToday ? theme.palette.units.sun.deep : nil,
                            borderWidth: 2
                        )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: day.accessibilityLabel))
            }
        }
        // `.wd.today i{animation:bump …}` — the arrival of today's tick, and nothing else moves. Under Reduce
        // Motion the tick is there rather than bumping into place: the outline above is what says which day it is,
        // so nothing is lost (ADR-0012).
        .animation(reduceMotion ? nil : HWMotion.easeBack.animation(.emphasised), value: days)
        .accessibilityElement(children: .contain)
    }

    /// The same seven days as text, which is what the screen shows above the accessibility threshold.
    private var rows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                HStack(spacing: 9) {
                    Image(systemName: day.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.hw(.body))
                        .foregroundStyle(day.isComplete ? theme.palette.units.sun.deep : theme.palette.surface.inkTertiary)
                        .accessibilityHidden(true)

                    Text(verbatim: day.accessibilityLabel)
                        .font(.hw(.body))
                        .foregroundStyle(theme.palette.surface.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// The design's `.confetti` — the falling paper over the completion screen.
///
/// **Pure SwiftUI and deliberately deterministic.** The design randomises every piece's position, size, and
/// duration; this derives them from the index, for the reason ``HWBrandGround``'s star field is transcribed rather
/// than randomised — a celebration that is a different picture on every render is a picture nobody can review, and
/// a preview that changes under you is not a reference.
///
/// **Under Reduce Motion it draws nothing, and the replacement is not nothing** (ADR-0012). The badge, the XP tile,
/// and the announcement the screen posts are all still there — which is exactly what the ADR asks for: "confetti → a
/// static celebratory badge carrying the XP figure". This view is the part that has no still form.
struct HWConfetti: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isFalling = false

    /// `for (let i = 0; i < 34; i++)`.
    private static let pieceCount = 34
    /// `translateY(560px)` — how far a piece falls before it is gone.
    private static let fallDistance: CGFloat = 560

    /// The six colours the design drops, as palette roles rather than the hex list beside them.
    private var colours: [Color] {
        [
            theme.palette.units.sun.base,
            theme.palette.units.mint.base,
            theme.palette.units.coral.base,
            theme.palette.units.violet.base,
            theme.palette.accent.base,
            theme.palette.accent.soft,
        ]
    }

    var body: some View {
        // Nothing at all under Reduce Motion — see the note above for what stands in its place.
        if reduceMotion {
            EmptyView()
        } else {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    ForEach(0..<Self.pieceCount, id: \.self) { index in
                        piece(index, in: proxy.size)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .onAppear { isFalling = true }
            // Decoration, and the design says so too (`aria-hidden="true"`).
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }

    private func piece(_ index: Int, in size: CGSize) -> some View {
        // A cheap deterministic spread: three coprime multipliers over the index, so the pieces do not line up in
        // a visible lattice and the same picture comes back every time.
        let across = Double((index * 37) % 100) / 100
        let width = 6 + CGFloat((index * 13) % 7)
        let duration = 1.6 + Double((index * 7) % 15) / 10
        let delay = Double((index * 11) % 6) / 10

        return RoundedRectangle(cornerRadius: 2)
            .fill(colours[index % colours.count])
            .frame(width: width, height: width * 1.6)
            .offset(x: across * size.width, y: isFalling ? Self.fallDistance : -20)
            .rotationEffect(.degrees(isFalling ? 720 : 0))
            .opacity(isFalling ? 0 : 1)
            .animation(.linear(duration: duration).delay(delay), value: isFalling)
    }
}

#if DEBUG
@MainActor
private func previewWeek(streak: Int) -> [HWWeekStrip.Day] {
    let labels = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
    let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Today", "Friday", "Saturday"]
    return labels.indices.map { index in
        let isComplete = index <= 4 && (4 - index) < streak
        return HWWeekStrip.Day(
            label: labels[index],
            isComplete: isComplete,
            isToday: index == 4,
            accessibilityLabel: "\(names[index]), \(isComplete ? "lesson finished" : "nothing finished")"
        )
    }
}

#Preview("The celebration — badge, tiles, and the week") {
    VStack(spacing: 22) {
        HWDoneBadge()

        HStack(spacing: 10) {
            HWCompletionStat(
                tone: .experience,
                value: "+50",
                caption: "XP earned",
                accessibilityLabel: "50 experience points earned"
            )
            HWCompletionStat(
                tone: .accuracy,
                value: "75%",
                caption: "Accuracy",
                accessibilityLabel: "75 percent accuracy"
            )
            HWCompletionStat(
                tone: .streak,
                value: "5",
                caption: "Day streak",
                accessibilityLabel: "5-day streak"
            )
        }

        HWWeekStrip(days: previewWeek(streak: 5))
    }
    .padding(22)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("A replay — nothing earned, and the strip says why") {
    VStack(spacing: 22) {
        HStack(spacing: 10) {
            HWCompletionStat(
                tone: .experience,
                value: "0",
                caption: "XP earned",
                accessibilityLabel: "No experience points earned"
            )
            HWCompletionStat(
                tone: .accuracy,
                value: "100%",
                caption: "Accuracy",
                accessibilityLabel: "100 percent accuracy"
            )
        }

        HWWeekStrip(days: previewWeek(streak: 1))
    }
    .padding(22)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("Confetti, over the badge it celebrates with") {
    ZStack {
        HWConfetti()
        HWDoneBadge()
    }
    .frame(height: 420)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the week strip is replaced by the same seven days as rows") {
    VStack(spacing: 22) {
        HWCompletionStat(
            tone: .experience,
            value: "+50",
            caption: "XP earned",
            accessibilityLabel: "50 experience points earned"
        )
        HWWeekStrip(days: previewWeek(streak: 5))
    }
    .padding(22)
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the week runs the other way") {
    HWWeekStrip(days: previewWeek(streak: 3))
        .padding(22)
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround())
        .hwTheme()
}
#endif
