import SwiftUI

/// The design's savings meter — one bar, red at the left and green at the goal, with a pin that slides along it
/// and a label that follows.
///
/// **Hand-built, and that is the decision rather than the shortcut** (ADR-0016). The donut is Swift Charts because
/// `SectorMark` is a mark the framework knows and publishes descriptors for. This is not a mark: it is a gradient
/// track, a pin, a label that stays inside the card at either end, and a pill — a shape the design invented.
/// Expressing it as a `RuleMark` with annotations would fight the framework for a layout it does not have, and
/// would still need every accessibility affordance written by hand.
///
/// **Nothing here is computed.** `position` arrives clamped, `percentageLabel` arrives formatted, and the verdict
/// arrives as a verdict — the prototype worked the last one out two different ways, which is defect D11. What this
/// view does with `position` is place a pin, which is geometry.
struct HWSavingsMeter: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How the month is going. Drives the pill's colour and nothing else — the *sentence* is the screen's, from
    /// the catalogue, because copy translates and a colour does not.
    enum Verdict: Sendable, Equatable {
        case low
        case onTrack
        case met
    }

    /// Where the pin sits, `0...1`, from the server.
    private let position: Double
    /// "₹23,000" — the **figure** in the floating label above the pin, and the value of the `Saved` row in the
    /// accessibility-size replacement. The word "saved" beside it is the component's, from
    /// ``HWComponentCopy/meterSaved(_:)``, so that two screens drawing this meter cannot word it differently.
    private let savedLabel: String
    /// The `0` at the left end and the goal at the right, both server-formatted.
    private let zeroLabel: String
    private let goalLabel: String
    /// "177% of goal" — the pill.
    private let percentageLabel: String
    private let verdict: Verdict
    /// The sentence under the bar, on the same row as the pill — the design's `.mf-l`.
    ///
    /// A `Text` and the **caller's**, for ``HWCard``'s subtitle's reason: which of three sentences a month gets
    /// is the server's verdict and the words are the screen's catalogue copy (ADR-0011, defect D11), so a
    /// component that owned the string would own a decision it cannot make. `nil` draws the pill alone, which is
    /// what a caller with no sentence to add gets.
    ///
    /// It is a slot here rather than a row the screen draws underneath because the design puts both on one line:
    /// `.meter-foot` is a `space-between` row, and a screen drawing the sentence below the component put the pill
    /// on a line of its own with white space beside it.
    private let foot: Text?
    /// What VoiceOver reads instead of the bar. One sentence, composed by the screen from catalogue copy and the
    /// server's display strings — a gradient with a pin on it has nothing a screen reader can do with it.
    private let accessibilityDescription: Text

    init(
        position: Double,
        savedLabel: String,
        zeroLabel: String,
        goalLabel: String,
        percentageLabel: String,
        verdict: Verdict,
        foot: Text? = nil,
        accessibilityDescription: Text
    ) {
        self.position = position
        self.savedLabel = savedLabel
        self.zeroLabel = zeroLabel
        self.goalLabel = goalLabel
        self.percentageLabel = percentageLabel
        self.verdict = verdict
        self.foot = foot
        self.accessibilityDescription = accessibilityDescription
    }

    /// `.meter{height:22px}` — the design's own thickness, and the bar is the card's biggest gesture.
    ///
    /// It was 14 here for a while, which is what the meter measured at in an earlier draft of the design; at that
    /// height the gradient is a hairline and the pin standing 6pt proud of it reads as a glitch rather than as a
    /// marker. 22 is what the design ships and what makes the red-to-green ramp legible as a ramp.
    private static let trackHeight: CGFloat = 22
    /// How wide the travelling label has turned out to be, measured rather than guessed.
    ///
    /// It is needed to keep the label inside the card: the design clamps its centre to `[half, width - half]` and
    /// then re-aims the arrow, and neither is possible without knowing the label's own width.
    @State private var labelWidth: CGFloat = 0
    /// `.meter-now{top:-6px;bottom:-6px;width:6px}` — the pin, standing proud of a 22pt track at both ends.
    private static let pinSize = CGSize(width: 6, height: 34)
    /// `box-shadow:0 0 0 3px rgba(255,255,255,.95)` — the halo that separates the pin from whichever stop of the
    /// ramp it has stopped on. Drawn as a wider capsule behind it, since SwiftUI has no spread-only shadow.
    private static let pinHalo: CGFloat = 3

    /// Whether the pin has travelled yet.
    ///
    /// **The design parks the pin at the red end and lets it slide to its value** — `place(false)` then
    /// `requestAnimationFrame(() => place(true))` — and that arrival is the whole of what the card animates. It is
    /// state rather than a transition because there is nothing to transition *from*: the value does not change
    /// while the screen is open, so without a first frame at zero the pin is simply already there.
    @State private var travelled = false

    /// Clamped **again**, here. The server sends it clamped; a pin drawn at 1.4 would sit outside the card, and a
    /// view that trusts a number it could check is a view that draws the one bad payload wrongly.
    private var clamped: Double { min(max(position, 0), 1) }

    /// Where the pin is drawn *now* — the red end until the arrival has run.
    private var drawnPosition: Double { travelled ? clamped : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            bar
                // Replaced above the size threshold by the same figures as rows (ADR-0012): a pin, a floating
                // label, and a pill inside a 22pt bar have nowhere to grow, and shrinking the labels to fit is
                // how a screen opts out of Dynamic Type while appearing to support it.
                .hwVisualisation {
                    alternative
                }

            ends

            footRow
        }
        .onAppear {
            guard !travelled else { return }
            if reduceMotion {
                // No travel, and no held-back first frame either: under Reduce Motion the pin is where it
                // belongs from the first paint. There is nothing to replace the movement *with* here — the
                // figure it would announce is already spelled out on the label and in the pill.
                travelled = true
            } else {
                withAnimation(HWMotion.easeOut.animation(.slow).delay(0.3)) { travelled = true }
            }
        }
    }

    // MARK: - The bar

    private var bar: some View {
        // `GeometryReader`, because the pin's place is a fraction of a width only the layout knows. The design does
        // the same thing with `getBoundingClientRect()`.
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width

                VStack(alignment: .leading, spacing: 4) {
                    travellingLabel(in: width)

                    ZStack(alignment: .topLeading) {
                        track
                        pin(in: width)
                    }
                    .frame(height: Self.pinSize.height, alignment: .center)
                }
            }
            .frame(height: Self.pinSize.height + Self.labelHeight + 4)
        }
        // **One element, and the bar is not it.** The track, the pin, and the label are three views drawing one
        // fact, so they are collapsed and the sentence the screen composed is read in their place.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("home.savings.meter.accessibilityLabel"))
        .accessibilityValue(accessibilityDescription)
    }

    /// The red→green ombré. The stops are the meter roles, which exist for this and for the four-segment split bar
    /// on Reports — a hand-mixed gradient here would be a second set of stops nobody could keep in step.
    private var track: some View {
        Capsule()
            .fill(
                // `.leading`/`.trailing` rather than `.left`/`.right`: a `UnitPoint` of `.leading` **is** mirrored
                // by the layout direction, so the "nothing saved" end of the gradient stays at the same end as the
                // pin's origin under Arabic. Fixed points would have left the red end on the physical left while
                // the pin travelled from the right.
                //
                // The design weights its five stops — `24% 50% 76%` — rather than spacing them evenly, which is
                // what keeps the amber band wide enough to read as "roughly halfway" instead of as a line between
                // orange and green.
                LinearGradient(
                    stops: Self.gradientStops(theme.palette.meter.stops),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            // `.meter::before` — the thin glass highlight along the top, which is what stops a 22pt gradient
            // reading as a flat painted strip.
            .overlay(alignment: .top) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.palette.surface.raised.opacity(0.34),
                                theme.palette.surface.raised.opacity(0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 6)
                    .padding(.horizontal, 3)
                    .padding(.top, 2)
            }
            .frame(height: Self.trackHeight)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    /// The design's `0% · 24% · 50% · 76% · 100%`, applied to whichever five colours the palette holds.
    ///
    /// A function over the array rather than five literals, so that a palette whose ramp gained or lost a stop
    /// still produces a gradient: the locations are spread evenly in that case, which is wrong-looking rather than
    /// crashing. `static` and pure so the mapping is assertable.
    static func gradientStops(_ colours: [Color]) -> [Gradient.Stop] {
        let locations: [Double] = [0, 0.24, 0.50, 0.76, 1]
        guard colours.count == locations.count else {
            let last = Double(max(colours.count - 1, 1))
            return colours.enumerated().map { .init(color: $1, location: Double($0) / last) }
        }
        return zip(colours, locations).map { .init(color: $0, location: $1) }
    }

    /// Room for the travelling label above the bar. A fixed height because the `GeometryReader` needs one, and the
    /// label is one short line at the sizes the bar is drawn at — above the threshold the whole thing is replaced.
    private static let labelHeight: CGFloat = 30

    /// `.meter-cap` / `#mtag` — the saved figure, **travelling with the pin**.
    ///
    /// This is a large part of why the meter is hand-built (ADR-0016): the label is centred on the pin, clamped so
    /// it stays inside the card at either extreme, and its arrow is then re-aimed at the pin it has stopped being
    /// centred on. The design does exactly that in `place()`; no chart annotation does any of it.
    private func travellingLabel(in width: CGFloat) -> some View {
        // The design's `place()`: the pin's centre, then the label's centre clamped inside the bar, then the
        // arrow's offset as the difference between them.
        let pinCentre = drawnPosition * width
        let half = labelWidth / 2
        let labelCentre = min(max(pinCentre, half), max(width - half, half))

        return Text(HWComponentCopy.meterSaved(savedLabel))
            // `.mtag{font-size:10.5px;font-weight:800}` on the galaxy fill — the design's own inversion, and the
            // one label on this card that is light on dark. It was card-coloured with hairline-bordered ink here,
            // which made the card's loudest figure its quietest thing.
            .font(.hw(.caption).weight(.heavy))
            .foregroundStyle(theme.palette.brand.ink)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .hwBox(fill: theme.palette.accent.deep, radius: .small, elevation: .medium)
            .overlay(alignment: .bottomLeading) {
                // `--arrow` — the pointer, moved back towards the pin by however far the label was clamped.
                Triangle()
                    .fill(theme.palette.accent.deep)
                    .frame(width: 10, height: 5)
                    .padding(.leading, max(0, pinCentre - labelCentre + half - 5))
                    .offset(y: 5)
                    .accessibilityHidden(true)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
            // Leading padding rather than an offset, for the reason the pin uses one: an offset does not mirror.
            .padding(.leading, max(0, labelCentre - half))
            .frame(height: Self.labelHeight, alignment: .bottom)
            // The bar below carries the whole sentence; a second reading of the figure would be the third.
            .accessibilityHidden(true)
    }

    /// `.meter-now` — the galaxy pin in its white halo, centred on its position.
    ///
    /// **`padding(.leading:)` rather than `offset(x:)`, and that is the RTL fix.** An offset's `x` is always
    /// screen-rightward whatever the layout direction, so under Arabic — where `.topLeading` has already moved the
    /// origin to the right edge — a positive offset pushed the pin a full track-width outside the card. Leading
    /// padding mirrors with the layout, which is what the design's `left: at%` does inside a `dir="rtl"` document.
    private func pin(in width: CGFloat) -> some View {
        // `background:var(--galaxy)` inside `box-shadow:0 0 0 3px rgba(255,255,255,.95)`. A spread-only shadow is
        // the one CSS shape SwiftUI has no equivalent for, so the halo is a wider capsule drawn behind.
        Capsule()
            .fill(theme.palette.accent.deep)
            .frame(width: Self.pinSize.width, height: Self.pinSize.height)
            .padding(Self.pinHalo)
            .background {
                Capsule().fill(theme.palette.surface.raised.opacity(0.95))
            }
            .hwElevation(.small)
            .overlay { ping }
            .padding(.leading, max(0, drawnPosition * width - Self.pinSize.width / 2 - Self.pinHalo))
            .accessibilityHidden(true)
    }

    /// `.meter-now::after` — one quiet pulse, so the eye finds the pin on a bar that is otherwise still.
    ///
    /// **Suppressed entirely under Reduce Motion, and there is nothing to replace it with.** It says nothing: the
    /// figure it draws attention to is printed on the label directly above it, so a user who never sees the pulse
    /// has lost no information (contrast `HWEntrance`, where the movement *is* the notification that something
    /// arrived).
    @ViewBuilder
    private var ping: some View {
        if !reduceMotion {
            Capsule()
                .strokeBorder(theme.palette.accent.deep, lineWidth: 2)
                // One `Double` from 0 to 1, with the scale and the opacity derived from it — a keyframe track
                // interpolates one animatable value, and two tracks over the same clock would be two things to
                // keep in step.
                .keyframeAnimator(initialValue: 0.0, repeating: true) { content, spread in
                    content
                        .scaleEffect(0.86 + spread * (1.4 - 0.86))
                        .opacity(0.42 * (1 - spread))
                } keyframes: { _ in
                    // `@keyframes ping{0%{opacity:.42;transform:scale(.86)} 70%,100%{opacity:0;scale(1.4)}}`
                    // over 3s, after the design's 1.5s delay.
                    KeyframeTrack {
                        LinearKeyframe(0.0, duration: 1.5)
                        CubicKeyframe(1.0, duration: 2.1)
                        LinearKeyframe(1.0, duration: 0.9)
                    }
                }
                .accessibilityHidden(true)
        }
    }

    /// `.meter-ends` — the zero and the goal, one at each end.
    ///
    /// The goal end is prefixed, as the design's `Goal <b>AED 2,000</b>` is: without it the row is two bare
    /// figures and nothing says which of them the bar's far edge means.
    private var ends: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: zeroLabel)
                .font(.hw(.micro).weight(.heavy))
                .tracking(0.5)
                .foregroundStyle(theme.palette.surface.inkTertiary)

            Spacer(minLength: 0)

            Text(HWComponentCopy.meterGoal(goalLabel))
                .font(.hw(.micro).weight(.heavy))
                .tracking(0.5)
                .foregroundStyle(theme.palette.surface.inkSecondary)
        }
        .textCase(.uppercase)
        .fixedSize(horizontal: false, vertical: true)
        // Read as part of the bar's own sentence, which already names the goal.
        .accessibilityHidden(true)
    }

    /// `.meter-foot` — the caller's sentence and the percentage pill, on one baseline-aligned row.
    ///
    /// The saved figure is **not** here: it travels with the pin, which is where the design puts it, and having it
    /// in both places printed the same string twice.
    private var footRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let foot {
                foot
                    .font(.hw(.body).weight(.medium))
                    .foregroundStyle(theme.palette.surface.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            // A third reading of what the bar above already says, so it is read by nothing. The sentence beside
            // it is not: it is the only place the card explains itself in words.
            pill.accessibilityHidden(true)
        }
    }

    /// `.mf-r` and its `.warn` / `.low` variants — **the same badge Reports draws**, so it is
    /// ``HWVerdictBadge`` (#21).
    ///
    /// The design gives `.mf-r` and `.m-badge` the same three soft/ink pairs, written twice in the CSS. This
    /// drew them a third way until Reports arrived — a saturated fill with milky ink, picked here rather than
    /// transcribed — which is a colour table with two owners about one verdict, the shape defect D11 took about
    /// a threshold table. One badge now, and ``verdictTint`` is the whole of what this view still decides.
    private var pill: some View {
        HWVerdictBadge(verdict: verdictTint, label: percentageLabel)
    }

    /// The design's three pill classes as the palette's three verdicts: unmodified `.mf-r` is the green one,
    /// `.warn` the amber, `.low` the red.
    ///
    /// A mapping rather than one shared enum, for the reason `HomeView` maps `HomeScreen.Savings.Verdict` onto
    /// this view's own: the live month's vocabulary and the design system's are allowed to move apart, and the
    /// place they meet is one expression a test can hand every case to.
    private var verdictTint: HWVerdictTint {
        switch verdict {
        case .low: .miss
        case .onTrack: .near
        case .met: .hit
        }
    }

    // MARK: - The alternative

    /// The same four facts as rows, for accessibility sizes. Text, so it scales the whole way to AX5.
    private var alternative: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("home.savings.saved.label", value: savedLabel)
            row("home.savings.goal.label", value: goalLabel)
            row("home.savings.progress.label", value: percentageLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element carrying the sentence the bar carries, so the two forms read identically.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("home.savings.meter.accessibilityLabel"))
        .accessibilityValue(accessibilityDescription)
    }

    private func row(_ label: LocalizedStringResource, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .hwLabel()
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: value)
                .font(.hw(.body).weight(.semibold))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// The label's pointer. A `Path` because the design's is a CSS triangle, which is a shape rather than a glyph.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#if DEBUG
private func previewMeter(_ position: Double, _ percentage: String, _ verdict: HWSavingsMeter.Verdict) -> some View {
    HWSavingsMeter(
        position: position,
        savedLabel: "₹23,000",
        zeroLabel: "₹0",
        goalLabel: "₹13,000",
        percentageLabel: percentage,
        verdict: verdict,
        foot: Text(verbatim: "You have put aside ₹23,000. Another ₹880 and you are there."),
        accessibilityDescription: Text(verbatim: "₹23,000 of a ₹13,000 goal, \(percentage)")
    )
}

#Preview("Savings meter — the three verdicts and both ends") {
    VStack(spacing: 30) {
        previewMeter(0, "0% of goal", .low)
        previewMeter(0.56, "56% of goal", .onTrack)
        previewMeter(1, "177% of goal", .met)
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the bar is replaced by rows") {
    previewMeter(0.56, "56% of goal", .onTrack)
        .padding()
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("RTL — the pin travels from the right") {
    previewMeter(0.56, "56% of goal", .onTrack)
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround())
        .hwTheme()
}
#endif