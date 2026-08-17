import SwiftUI

/// The design's `countTo()` — a figure that **rolls up to its value** instead of appearing at it.
///
/// ```js
/// function countTo(el, to, prefix = '') {
///   const from = Number(String(el.dataset.v || 0));
///   el.dataset.v = to;
///   if (reduced || from === to) { el.textContent = prefix + money(to); return; }
///   const t0 = performance.now(), dur = 700;
///   (function step(t) {
///     const p = Math.min(1, (t - t0) / dur), eased = 1 - Math.pow(1 - p, 3);
///     el.textContent = prefix + money(from + (to - from) * eased);
///     if (p < 1) requestAnimationFrame(step);
///   })(t0);
/// }
/// ```
///
/// **It never holds a number, and that is the whole design of it.** The design's version interpolates between
/// two amounts and re-formats the figure on every frame, which is a money formatter — `AccessibilityTests`
/// forbids a view from so much as naming `minor` or `exponent`, and ADR-0003 leaves the client with nothing to
/// format with. So what arrives here is the server's finished display string, and the animation is
/// `contentTransition(.numericText)` rolling **the glyphs that are already in it**: the first frame is a copy of
/// that same string with each digit replaced by a zero, the last frame is the string itself, and every frame
/// between them is the platform interpolating one glyph into another. Both ends are strings the client was
/// handed; the client authored neither.
///
/// **Two things make it roll**, which is the design's own pair:
///
/// - **Arriving.** `.onAppear` parks the figure at zeros and releases it on the next turn of the main actor, so
///   opening Expenses — from another tab, or by coming back out of a category — counts every figure up. That is
///   the design's own `place(false); requestAnimationFrame(() => place(true))`, which exists for the same reason:
///   two state changes in one transaction coalesce, and the animation never runs.
/// - **Changing.** A write answers with a new payload (ADR-0020), so the string changes and the same transition
///   rolls **from the old figure to the new one** — which is `countTo(from, to)` without a line of arithmetic.
///
/// **The correct figure is the resting state, and the zeros are the departure from it** — not the other way
/// round, which is how this was first written and what looking at a render caught. `ImageRenderer` does not run
/// the view lifecycle, so `onAppear` never fired and every figure on the card came back reading `₹0,000`: a
/// screen full of wrong numbers, pinnable by a snapshot and one platform quirk away from being what a user sees.
/// Parking *from* the truth inverts which way that fails. If the roll never runs the figure is simply right, and
/// the worst case is a missing flourish rather than a card claiming somebody has spent nothing.
///
/// `monospacedDigit()` is `font-variant-numeric:tabular-nums`, which the design sets on every figure it counts
/// and which is load-bearing here rather than cosmetic: proportional digits change width as they roll, so an
/// eight-becoming-a-three would shuffle the whole card sideways for the length of the count.
///
/// **Under Reduce Motion the figure is simply there.** This is the shape ADR-0012's replace-never-remove has
/// nothing to replace: the roll carries no information — it announces no change and confirms no action, and the
/// value it lands on is on screen either way. It is also read by nothing, because a caller wraps its figures in
/// an `accessibilityElement(children: .ignore)` and supplies the display string as the element's value; a
/// half-rolled figure never reaches VoiceOver.
struct HWCountingFigure: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The server's display string — `₹5,539`, `+AED 900`. Rendered verbatim (ADR-0003).
    let figure: String

    /// Whether the figure is currently held at the zeroed copy, waiting to be released.
    ///
    /// **False by default**, which is the whole of the safety argument above: nothing has to happen for the
    /// figure to be right.
    @State private var isParked = false

    /// `dur = 700` with `1 - (1 - p)³`, which is the shape `--ease-out` has and the ``HWDuration/slow`` step is
    /// the scale's nearest — the design's own duration cluster for something arriving (`HWMotion`).
    private static let roll = HWMotion.easeOut.animation(.slow)

    /// What is drawn this frame: the figure, or the zeroed copy it counts up from.
    private var shown: String {
        isParked ? Self.zeroed(figure) : figure
    }

    var body: some View {
        Text(verbatim: shown)
            .monospacedDigit()
            // `countsDown: false` — every figure on this screen is counted **up** from zero, and a total that
            // fell after a deletion still reads as a total settling rather than as a countdown.
            .contentTransition(.numericText(countsDown: false))
            .animation(reduceMotion ? nil : Self.roll, value: shown)
            .onAppear(perform: park)
    }

    /// Drops to the zeroed copy without animating, then counts back up.
    ///
    /// The park is inside a transaction with animations disabled, so the figure does not visibly roll *down*
    /// before it rolls up. The release is after a yield, which is what stops the two mutations coalescing into no
    /// change at all — `place(false); requestAnimationFrame(() => place(true))`, in the design.
    ///
    /// **Both halves are inside the one `Task`, and that is the second correction looking at a render forced.**
    /// Parking synchronously and releasing asynchronously moves the hazard rather than removing it: `onAppear`
    /// *does* run under `ImageRenderer`, so the figure parked at `₹0,000` and the release never got a turn — a
    /// card of zeros again, by a different route. With both inside the same task there is one thing that can fail
    /// and it fails safely: a context that never runs it never parks either, so the figure stands at its value and
    /// the only loss is the roll. A yield that is too short to let the parked frame commit costs the same nothing.
    private func park() {
        guard !reduceMotion else { return }

        Task { @MainActor in
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) { isParked = true }

            await Task.yield()

            isParked = false
        }
    }

    /// The same string with **every digit replaced by a zero** — the odometer's parked position.
    ///
    /// Character substitution rather than formatting, and the distinction is the one that matters: the symbol,
    /// the grouping separators, the decimal mark, any sign, and the bidirectional marks a server-formatted
    /// Arabic string carries all stay exactly where the server put them, and the digit *count* is unchanged —
    /// which is what lets `numericText` pair the glyphs up positionally instead of cross-fading two strings of
    /// different lengths.
    ///
    /// `Character.isWholeNumber` rather than a range check on `0...9`, so this is a question about the character
    /// and not an assumption about which digits a string may contain. `static` and pure, so the substitution is
    /// something a test hands every shape of display string to.
    static func zeroed(_ figure: String) -> String {
        String(figure.map { $0.isWholeNumber ? "0" : $0 })
    }
}

#if DEBUG
/// The previews put the ground in a `ZStack` rather than reaching for `.background(_:)`, and that is not a style
/// choice: `ComponentVocabularyTests` asks every file in this layer that *paints* to resolve its colours through
/// the palette, and this component deliberately paints nothing — the caller owns the font and the ink, as every
/// figure on Expenses is a different size in a different colour. A preview background would make the scan read
/// this file as one that paints and then fail it for painting through nobody.
private struct HWCountingPreview: View {
    private static let quiet = ["₹5,539", "₹3,529", "₹2,010"]
    private static let busier = ["₹8,120", "₹4,000", "₹4,120"]

    @State private var figures = Self.quiet

    var body: some View {
        ZStack {
            HWPreviewGround()

            VStack(spacing: 18) {
                ForEach(figures, id: \.self) { figure in
                    HWCountingFigure(figure: figure)
                        .font(.hw(.display))
                }

                Button("Roll them to new figures") {
                    figures = figures == Self.quiet ? Self.busier : Self.quiet
                }
            }
            .padding(24)
        }
    }
}

/// One figure at rest beside the parked position it counts up from, for every shape of display string the server
/// sends: a leading symbol, a decimal mark, an explicit sign, and a currency with no minor unit at all.
private struct HWZeroedPreview: View {
    var body: some View {
        ZStack {
            HWPreviewGround()

            VStack(alignment: .leading, spacing: 10) {
                ForEach(["₹5,539", "AED 12,340.50", "+AED 900", "¥1,200"], id: \.self) { figure in
                    HStack(spacing: 14) {
                        Text(verbatim: HWCountingFigure.zeroed(figure))
                        Text(verbatim: figure)
                    }
                    .font(.hw(.subheading))
                    .monospacedDigit()
                }
            }
            .padding(24)
        }
    }
}

#Preview("A figure counting up, and rolling to a new one") {
    HWCountingPreview().hwTheme()
}

#Preview("The parked position every roll starts from") {
    HWZeroedPreview().hwTheme()
}

#Preview("AX3 — a counted figure scales like any other text") {
    HWCountingFigure(figure: "₹5,539")
        .font(.hw(.display))
        .padding(24)
        .dynamicTypeSize(.accessibility3)
        .hwTheme()
}

// The symbol stays where the server put it: this substitutes digits and moves nothing (ADR-0003, ADR-0011).
#Preview("RTL — the string is the server's, and only its digits change") {
    HWCountingFigure(figure: "₹5,539")
        .font(.hw(.display))
        .padding(24)
        .environment(\.layoutDirection, .rightToLeft)
        .hwTheme()
}
#endif
