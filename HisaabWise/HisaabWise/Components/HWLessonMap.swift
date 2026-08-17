import SwiftUI

/// What state a lesson node is drawn in — the design's `.done` / `.current` / `.locked`.
///
/// A component-owned enum rather than the payload's own, for `HWSavingsMeter.Verdict`'s reason: the caller says
/// what the lesson *is* and the component says what that looks like. `LearnView` maps
/// `LearnScreen.LessonState` onto it, and a test asserts the mapping is total.
enum HWLessonNodeState: Sendable, Equatable, CaseIterable {
    /// `.node.done` — every question answered. Drawn in the unit's accent with a tick.
    case completed
    /// `.node.current` — open, with however much of its ring is lit.
    case available
    /// `.node.locked` — the padlock, in the locked greys.
    case locked
}

/// The accent wash a unit band and a lesson face are both filled with, or the locked fill in its place.
///
/// One function because both are the design's `linear-gradient(var(--acc), var(--acc-deep))` and differ only in
/// which locked colour stands in for it — the band takes `locked` and the face the softer `lockedSoft`, which is
/// the design's own pair. Two copies of the same `AnyShapeStyle` construction is one of them being changed alone.
///
/// **`.topLeading` → `.bottomTrailing` rather than the design's 140°/155°**: those two `UnitPoint`s mirror with the
/// layout direction and a degree does not (ADR-0011), and the tilt is not what the reader is looking at.
private func hwAccentGround(
    _ accent: HWPalette.UnitAccent,
    isLocked: Bool,
    lockedFill: Color
) -> AnyShapeStyle {
    guard !isLocked else { return AnyShapeStyle(lockedFill) }
    return AnyShapeStyle(
        LinearGradient(colors: [accent.base, accent.deep], startPoint: .topLeading, endPoint: .bottomTrailing)
    )
}

/// The design's `.unit-head` — the gradient band that opens a unit, with its number, its title, and the button
/// that opens the unit guide.
///
/// **The locked treatment is a deliberate departure.** The design draws a locked header as
/// `linear-gradient(#A9B2C7, #8B95AE)` with white text, which is about 2.9:1 — under the 4.5:1 the rest of this
/// palette is asserted against (`ColorAssetTests`). There is no token for those two greys either. So a locked
/// header is the `locked` role with the surface's own ink on it, which passes comfortably and keeps the two
/// states as far apart as the design intends.
struct HWUnitHeader: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The `1`…`5` in the `.unit-n` tile, already a string.
    ///
    /// **Spelled where it is computed, not here** — the convention every interpolated key in this app relies on.
    /// A unit index has no separator and no plural, which is why `String(_:)` is the whole of its formatting and
    /// it does not arrive from the server the way XP does.
    private let number: String
    /// "Unit 3 · Debt & Credit" — the `.unit-cap`, assembled from a catalogue entry by the screen.
    private let caption: Text
    /// Server content, in the reader's language.
    private let title: String
    private let subtitle: String
    private let tint: HWUnitTint
    private let isUnlocked: Bool
    /// `.unit-guide` — opens the sheet listing the unit's lessons.
    private let onOpenGuide: () -> Void

    init(
        number: String,
        caption: Text,
        title: String,
        subtitle: String,
        tint: HWUnitTint,
        isUnlocked: Bool,
        onOpenGuide: @escaping () -> Void
    ) {
        self.number = number
        self.caption = caption
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.isUnlocked = isUnlocked
        self.onOpenGuide = onOpenGuide
    }

    private var accent: HWPalette.UnitAccent { theme.palette.units.accent(tint) }

    /// `background:linear-gradient(140deg,var(--acc),var(--acc-deep))`, or the flat locked role.
    private var ground: AnyShapeStyle {
        hwAccentGround(accent, isLocked: !isUnlocked, lockedFill: theme.palette.feedback.locked)
    }

    private var ink: Color {
        isUnlocked ? theme.palette.brand.ink : theme.palette.surface.ink
    }

    /// The tile behind the number, and **the raised surface rather than the design's translucent white**.
    ///
    /// The design draws `rgba(255,255,255,.22)` over the accent, and there is no white-alpha token to spell that
    /// with — `brand.separatorStrong` was the nearest and rendered the numeral as a barely-visible ghost on the
    /// sun band. A solid white tile with the accent's own deep ink in it is legible on all five accents, and it
    /// is the pairing the design itself uses for the guide sheet's `.gi-n` chip. **Looking at it running is what
    /// found this.**
    private var tile: Color { theme.palette.surface.raised }

    private var numberInk: Color {
        isUnlocked ? accent.deep : theme.palette.surface.ink
    }

    var body: some View {
        HStack(spacing: 13) {
            Text(verbatim: number)
                .font(.hw(.subheading))
                .foregroundStyle(numberInk)
                .monospacedDigit()
                .frame(minWidth: 40, minHeight: 40)
                .hwBox(fill: tile, radius: .medium)
                // The number is in the caption beside it — "Unit 3" — so reading the tile as well says it twice.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                // **The eyebrow role is not used here**, and that is a contrast decision rather than a shortcut.
                // `hwEyebrow` resolves its own colour and cannot be overridden from outside (a style that paints
                // inside itself); its `brand` value is the design's sky blue, which on a warm accent band is about
                // 1.6:1 and was illegible the first time this was looked at. The band's own ink at the eyebrow's
                // type step is the same line, as readable as the title above it.
                caption
                    .font(.hw(.micro).weight(.bold))
                    .tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: title)
                    .font(.hw(.subheading))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                // Full opacity, where the design draws `.88`: small text on a saturated band has no contrast to
                // give away.
                Text(verbatim: subtitle)
                    .font(.hw(.caption))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The band's three lines are one heading, which is what the design's `.unit-head` is.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            // **`surface` on both**, which is the same finding as the number tile: the `brand` icon button is a
            // translucent light tile with sky-blue ink, drawn for the galaxy ground — and a unit band is neither
            // of the design's two surfaces. A white tile with the accent's ink reads on all five.
            HWIconButton(
                HWComponentCopy.unitGuide,
                systemImage: "book",
                action: onOpenGuide
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hwBox(fill: ground, radius: .extraLarge, elevation: isUnlocked ? .medium : .small) {
            // Only on a live band. On the locked grey it would read as a smudge rather than as light.
            if isUnlocked { bloom }
        }
        .accessibilityElement(children: .contain)
    }

    /// `.unit-head::after` — the soft white light in the band's top corner, drifting on a nine-second loop.
    ///
    /// Drawn through ``SwiftUI/View/hwBox(fill:radius:border:borderWidth:borderDash:elevation:shine:)``'s `shine`
    /// slot, because that is where `overflow:hidden` already is: the design clips the light to the band's own
    /// radius, and a `clipShape` here would be the same rounding written a second time.
    ///
    /// **Placed with negative padding rather than with an offset.** `.trailing` mirrors under Arabic and an
    /// `offset(x:)` does not — the fix ``HWSavingsMeter`` records for its pin (ADR-0011). For the same reason the
    /// design's 14pt *sideways* drift is dropped and its 12pt vertical drift kept: a blurred circle sliding
    /// sideways is not what the reader is looking at, and it is not worth a direction to negate.
    private var bloom: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [theme.palette.brand.ink.opacity(0.3), theme.palette.brand.ink.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: Self.bloomDiameter * 0.5
                )
            )
            .frame(width: Self.bloomDiameter, height: Self.bloomDiameter)
            .hwDrifts(suppressed: reduceMotion)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            // `top:-92px;right:-46px` — most of it hangs outside the band and is clipped away, which is what
            // leaves a wash in the corner rather than a disc on the band.
            .padding(.top, -92)
            .padding(.trailing, -46)
    }

    /// `.unit-head::after{width:170px;height:170px}`.
    private static let bloomDiameter: CGFloat = 170
}

/// The design's `.track` — the zig-zagging path of lesson nodes, with the dotted line that joins them.
///
/// **Replaced rather than shrunk at accessibility sizes** (ADR-0012). A 78pt ring with a wrapping label under it,
/// offset 56pt off the centre line, has nowhere to grow: the labels collide before AX3. Above the threshold the
/// path is gone and the same lessons are a plain column of ``HWLessonRow``s, which is text and scales the whole
/// way to AX5. The same rows are installed as the path's `accessibilityRepresentation` below it, so a VoiceOver
/// user reads the list at every size.
///
/// **The connectors are measured, not calculated.** The design draws them from `getBoundingClientRect()` after
/// layout for the same reason this reads each node's frame out of a named coordinate space: the nodes' positions
/// depend on how the labels wrapped. Measuring also makes the path mirror for nothing — the frames come back
/// already mirrored under Arabic, where a hand-computed `x` would have needed the direction read and negated.
///
/// That last claim is true **only because ``connectors`` pins its drawing to `leftToRight`**, which it did not
/// always do. A measured frame and a drawn `Path` are in two different spaces under RTL; see the note there.
struct HWLessonTrack: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One node on the path. Everything both the path and its replacement draw, and nothing either derives.
    struct Node: Sendable, Equatable, Identifiable {
        let id: String

        /// The lesson's number within its unit, **from the payload** — the row that replaces this node at
        /// accessibility sizes draws it, and `index + 1` there was the second of the two places review found the
        /// client deriving a figure the reader sees (ADR-0020).
        let number: String

        /// Server content — the lesson's title.
        let title: String
        /// Server content — "2 of 5 questions answered". The node's VoiceOver value, and the row's second line.
        let progressLabel: String
        let systemImage: String
        let state: HWLessonNodeState
        /// How many arcs the ring is drawn in, and how many are lit. **Both from the payload** (ADR-0020): a
        /// count is a calculation, and a ring whose segments and fill came from different responses is a ring
        /// with two owners.
        let segments: Int
        let filledSegments: Int
        /// `.has-start` — whether the **START** badge sits above this node. At most one node on the whole map.
        let isNext: Bool
    }

    private let tint: HWUnitTint
    private let nodes: [Node]
    /// The `START` badge's word. App copy, so the caller supplies it.
    private let startLabel: LocalizedStringResource
    private let onSelect: (Node) -> Void

    init(
        tint: HWUnitTint,
        nodes: [Node],
        startLabel: LocalizedStringResource,
        onSelect: @escaping (Node) -> Void
    ) {
        self.tint = tint
        self.nodes = nodes
        self.startLabel = startLabel
        self.onSelect = onSelect
    }

    /// The design's `OFFSETS` — lessons alternate 56pt either side of the centre line.
    ///
    /// Expressed as an **alignment** rather than as an `offset(x:)`, which is the RTL fix `HWSavingsMeter` records
    /// for its pin: an offset's `x` is screen-rightward whatever the layout direction, while `.leading` and
    /// `.trailing` mirror.
    private static let swing: CGFloat = 56

    /// `nonisolated`, because the closure that measures a node's frame is `Sendable` and a `View`'s statics are
    /// main-actor-isolated by its conformance. A `String` constant is safe to read from anywhere.
    private nonisolated static let space = "hwLessonTrack"

    /// `.track{padding:34px 0 18px}` — room above the first node for its **START** flag, which is an overlay and
    /// so reserves none of its own.
    private static let topInset: CGFloat = 34
    private static let bottomInset: CGFloat = 18

    /// `.node-row.has-start{margin-top:20px}` — the extra the design gives a row carrying the flag, on top of the
    /// 30pt between rows. The flag needs about 36 and gets 50.
    private static let flagRoom: CGFloat = 20

    /// `.start{bottom:calc(100% + 6px)}` — between the tip of the flag's tail and the top of the ring.
    private static let flagGap: CGFloat = 6

    /// `.start::after{border:6px solid transparent}` — a 12×6 wedge, so the flag points at its node.
    private static let tailWidth: CGFloat = 12
    private static let tailHeight: CGFloat = 6

    /// Each node's centre in the track's own space, measured after layout.
    @State private var centres: [String: CGPoint] = [:]

    private var accent: HWPalette.UnitAccent { theme.palette.units.accent(tint) }

    var body: some View {
        path
            .hwVisualisation {
                alternative
            }
    }

    // MARK: - The path

    private var path: some View {
        VStack(spacing: 30) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                nodeColumn(node, isLeading: index.isMultiple(of: 2))
            }
        }
        .frame(maxWidth: .infinity)
        .coordinateSpace(.named(Self.space))
        .background { connectors }
        .padding(.top, Self.topInset)
        .padding(.bottom, Self.bottomInset)
    }

    private func nodeColumn(_ node: Node, isLeading: Bool) -> some View {
        VStack(spacing: 6) {
            HWLessonNode(node: node, tint: tint) { onSelect(node) }
                .onGeometryChange(for: CGPoint.self) { proxy in
                    let frame = proxy.frame(in: .named(Self.space))
                    return CGPoint(x: frame.midX, y: frame.midY)
                } action: { centres[node.id] = $0 }
                // **An overlay rather than a row above the node**, which is what
                // `.start{position:absolute;bottom:calc(100% + 6px)}` is. In the flow it pushed the node down and
                // the measured centre with it, so one lesson on the whole map sat lower than its neighbours and
                // the two connectors either side of it kinked. Out of the flow, the flag is decoration over a
                // node whose position nothing about the flag changes.
                .overlay(alignment: .top) {
                    if node.isNext { startFlag }
                }

            Text(verbatim: node.title)
                .font(.hw(.caption))
                .foregroundStyle(
                    node.state == .locked ? theme.palette.surface.inkTertiary
                        : theme.palette.surface.inkSecondary
                )
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 130)
                // The node above carries the title as its label; a second reading would be the third thing
                // VoiceOver says about one lesson.
                .accessibilityHidden(true)
        }
        // `.node-row{transform:translateX(var(--x))}`, as an alignment inside the full width so it mirrors.
        .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
        .padding(isLeading ? .leading : .trailing, Self.swing)
        // The room the flag hangs into. Reserved by the row rather than by the flag, because the flag is an
        // overlay and an overlay reserves nothing — without this it would ride over the label of the row above.
        .padding(.top, node.isNext ? Self.flagRoom : 0)
    }

    /// `.start` — the hopping **START** flag above the cursor, and the tail that points it at the node.
    ///
    /// **It hops.** An earlier build dropped the design's 1.6s loop on the reading that a bordered flag in the
    /// unit's accent is already the loudest thing on the screen. It is — and the hop is still what makes the eye
    /// land on it out of fifteen lessons, so the loop is the design's and it is back. Suppressed under Reduce
    /// Motion rather than replaced, for the reason ``HWAmbientLoop`` sets out: nothing in it is a fact, and the
    /// same sentence reaches VoiceOver either way through the node's own hint.
    ///
    /// The tail is `.start::after{top:100%;border-top-color:var(--acc)}` — a wedge hanging out of the flag's
    /// bottom edge into the gap below it, in the same accent as the border, so the flag points rather than floats.
    /// It hops with the flag, as a pseudo-element of it does in the design.
    ///
    /// **Collapsed to nothing and hung upward, rather than offset by its own height.** The flag's height is the
    /// reader's type size, so an offset would have to be measured — and a measured offset is a frame late, which
    /// on the first pass drew the flag *over* the ring it is supposed to point at. `.frame(height: 0,
    /// alignment: .bottom)` says the same thing without a number: the flag's bottom edge is the whole of its
    /// zero-height box, so aligning that box to the node's top hangs the flag above it at every Dynamic Type step.
    /// An `alignmentGuide` was tried first and landed the flag on the ring; **looking at it running is what found
    /// this**, and what says the arithmetic-free version is the one to keep.
    private var startFlag: some View {
        Text(startLabel)
            .font(.hw(.micro).weight(.heavy))
            .foregroundStyle(accent.deep)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .hwBox(
                fill: theme.palette.surface.raised,
                radius: .small,
                border: accent.base,
                borderWidth: 2,
                elevation: .medium
            )
            .overlay(alignment: .bottom) {
                Triangle()
                    .fill(accent.base)
                    .frame(width: Self.tailWidth, height: Self.tailHeight)
                    .offset(y: Self.tailHeight)
            }
            .hwBobs(suppressed: reduceMotion)
            // Zero-height, bottom-aligned: the flag hangs out of the top of its own box. See the note above.
            .frame(height: 0, alignment: .bottom)
            // And the box's bottom clears the ring by the gap, with the tail filling it.
            .offset(y: -(Self.flagGap + Self.tailHeight))
            // The node below says it is the next lesson in its own hint; this is the visual half.
            .accessibilityHidden(true)
    }

    /// `.links` — the dotted curves, one per consecutive pair, coloured where the lesson above is finished.
    ///
    /// Two `Path`s rather than one so the finished stretch of the path can be the unit's accent, as the design's
    /// `.is-done` does. Decorative in full: everything they convey is in each node's own state.
    private var connectors: some View {
        ZStack {
            curves { !$0.isDone }
                .stroke(theme.palette.surface.separatorStrong, style: Self.stroke)
            curves(\.isDone)
                .stroke(accent.base.opacity(0.65), style: Self.stroke)
        }
        // **The two spaces this component works in do not agree, and this is where they are made to.**
        //
        // `GeometryProxy.frame(in:)` reports **visual** coordinates — x grows rightward whatever the layout
        // direction, so a `.leading` node under Arabic measures a *large* x. A `Shape`, though, is drawn in
        // **layout** coordinates: SwiftUI mirrors `Path` content under RTL, so `x: 0` lands at the right edge.
        // Measured centres fed into a path therefore came out reflected, and every connector on the screen was
        // drawn on the wrong side of its nodes.
        //
        // Pinning the drawing to `leftToRight` puts the path in the same space the measurements came from. The
        // curves still mirror — the *centres* are already mirrored by the layout, which is what makes the whole
        // path follow the nodes with no direction of its own (ADR-0011). Nothing here is text, so this is the
        // whole of what the environment value affects.
        //
        // **The mismatch predates the curves.** The straight-down connectors this replaced had it too; a
        // near-vertical line reflected about the centre looks like a near-vertical line, so it read as a slightly
        // odd path rather than as a bug. A one-line probe of a leading marker against a `Path` at `x: 0` is what
        // settled it — the doc comment above used to assert the opposite.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    /// `stroke-dasharray:2 15` at `stroke-width:4.5`, round caps — a line of dots rather than dashes.
    private static let stroke = StrokeStyle(lineWidth: 4.5, lineCap: .round, dash: [2, 15])

    /// `R` in the design's `drawLinks` — "node radius plus a little breathing room", which is where a connector
    /// leaves one ring and lands on the next.
    ///
    /// Built from the **node's own** diameter rather than restating 39 here: the dots stopping cleanly at the ring
    /// is only true while the two agree, and two copies of 78 in one file agree until somebody changes one.
    private static let clearance: CGFloat = 8
    private static var reach: CGFloat { HWLessonNode.diameter / 2 + clearance }

    /// How far the curve is turned off the straight line as it leaves a ring, and back as it arrives — the
    /// design's `-side * 1.0` and `side * 0.75`, in radians.
    ///
    /// **The asymmetry is what keeps the dots off the captions.** Turned a full radian on the way out, the line
    /// leaves the ring at its outer side and slightly *above* centre — clear of the title underneath it — bows
    /// out past both, and comes back down into the next ring from very nearly straight above.
    ///
    /// Not `private`, for ``turned(_:by:)``'s reason: the asymmetry is the whole mechanism, and `LearnViewTests`
    /// asserts that the two have not quietly become one number.
    nonisolated static let outboundTurn = 1.0
    nonisolated static let inboundTurn = 0.75

    /// The curves whose pair passes `include`.
    ///
    /// **The design's own arithmetic, and the second attempt at this.** The first drew a cubic straight down from
    /// the bottom of one column into the top of the next ring. It needed each column's bottom measured as well as
    /// its centre, it read as a column of near-vertical lines rather than as a path, and it still crowded the
    /// captions. This bows each link *outwards* — right-hand side when the next lesson is to the right, left-hand
    /// side when it is to the left — so the dots sweep around the ring and its caption instead of squeezing past.
    ///
    /// Every term comes off the two measured centres, so there is no direction in it to mirror: under Arabic the
    /// frames arrive mirrored, `side` flips with them, and the whole path follows (ADR-0011).
    ///
    /// SVG and SwiftUI both put `+y` downward and turn a vector the same way, so the design's `rot` transcribes
    /// with no sign to flip.
    private func curves(_ include: (Link) -> Bool) -> Path {
        Path { path in
            for link in links where include(link) {
                let delta = CGPoint(x: link.to.x - link.from.x, y: link.to.y - link.from.y)
                // `|| 1` in the design — two nodes measured at the same point would divide by zero.
                let distance = max(hypot(delta.x, delta.y), 1)
                let unit = CGPoint(x: delta.x / distance, y: delta.y / distance)

                // Which way the next lesson lies, and so which side the bow goes.
                let side: CGFloat = delta.x >= 0 ? 1 : -1
                let outbound = Self.turned(unit, by: -side * Self.outboundTurn)
                let inbound = Self.turned(CGPoint(x: -unit.x, y: -unit.y), by: side * Self.inboundTurn)

                let start = CGPoint(
                    x: link.from.x + outbound.x * Self.reach,
                    y: link.from.y + outbound.y * Self.reach
                )
                let end = CGPoint(x: link.to.x + inbound.x * Self.reach, y: link.to.y + inbound.y * Self.reach)

                // The perpendicular the bow pushes along, how far it pushes, and how far each end carries on in
                // the direction it left or will arrive in. The design's `bow * 0.5` is folded into the one
                // fraction, so the number here is the one that decides how round the curve is.
                let normal = CGPoint(x: side * unit.y, y: -side * unit.x)
                let bow = distance * 0.25
                let lead = distance * 0.3

                path.move(to: start)
                path.addCurve(
                    to: end,
                    control1: CGPoint(
                        x: start.x + outbound.x * lead + normal.x * bow,
                        y: start.y + outbound.y * lead + normal.y * bow
                    ),
                    control2: CGPoint(
                        x: end.x + inbound.x * lead + normal.x * bow,
                        y: end.y + inbound.y * lead + normal.y * bow
                    )
                )
            }
        }
    }

    /// A vector turned by `angle` radians — the design's `rot`, which it writes inline twice.
    ///
    /// `nonisolated` so `LearnViewTests` can assert the rotation rather than assert a picture of it: the bow is the
    /// one piece of this component that is arithmetic rather than layout, and arithmetic is what a test can hold.
    nonisolated static func turned(_ vector: CGPoint, by angle: Double) -> CGPoint {
        let cosine = cos(angle)
        let sine = sin(angle)
        return CGPoint(
            x: vector.x * cosine - vector.y * sine,
            y: vector.x * sine + vector.y * cosine
        )
    }

    /// One connector: the two ring centres it runs between, and whether the lesson it leaves is finished.
    private struct Link {
        let from: CGPoint
        let to: CGPoint
        let isDone: Bool
    }

    /// The pairs that have both centres measured. Before the first layout pass there are none, and drawing
    /// nothing is right — a curve to a node whose position is not known yet would be a line to the origin.
    ///
    /// **Centres only.** The bow leaves each ring at its own outer edge, so where the caption underneath ends is
    /// no longer something this has to know — which is one measurement fewer and one collision that cannot happen.
    private var links: [Link] {
        zip(nodes, nodes.dropFirst()).compactMap { above, below in
            guard let from = centres[above.id], let to = centres[below.id] else { return nil }
            return Link(from: from, to: to, isDone: above.state == .completed)
        }
    }

    // MARK: - The replacement

    /// The same lessons as rows: what the screen shows above the size threshold, and what VoiceOver reads below
    /// it (ADR-0012).
    private var alternative: some View {
        VStack(spacing: 8) {
            ForEach(nodes) { node in
                HWLessonRow(
                    number: node.number,
                    title: node.title,
                    detail: node.progressLabel,
                    state: node.state,
                    isNext: node.isNext,
                    tint: tint
                ) {
                    onSelect(node)
                }
            }
        }
    }
}

/// One `.node` — the segmented progress ring, and the face inside it.
///
/// **A locked node is still pressable**, which is the design's own behaviour rather than a liberty: its `<button>`
/// is `disabled`, and its container's click handler then says "Finish the lesson before it to unlock this one."
/// A SwiftUI `.disabled(true)` button fires nothing at all, so the reader would tap a padlock and be told
/// nothing. Enabled-with-a-refusal is the same experience the design delivers by a stranger route.
///
/// **Internal rather than file-private**, which it was until the face was found crossing its own ring: the four
/// numbers that decide whether it does are a relationship rather than four constants, and ``ringClearance`` is
/// only assertable from a test if the type it lives on is visible to one.
struct HWLessonNode: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let node: HWLessonTrack.Node
    let tint: HWUnitTint
    let action: () -> Void

    private var accent: HWPalette.UnitAccent { theme.palette.units.accent(tint) }

    /// `.node{width:78px;height:78px}`.
    ///
    /// ``diameter`` is not `private`: the track reads it to know where a connector has to stop, and a second copy
    /// of 78 in the same file is two numbers that agree until one of them changes.
    static let diameter: CGFloat = 78

    /// `.ring circle{stroke-width:6}`.
    private static let ringWidth: CGFloat = 6

    /// `.face{width:58px;height:58px}` — **54 here, and the 4pt is the whole reason the number is written down.**
    ///
    /// The design's face is 58 across with a `0 6px 0 0` solid block under it, so it reaches 35pt from the centre
    /// while the inside of the ring is at 33: in the browser the face crosses its own ring by about 2pt along the
    /// bottom. On a phone that reads as a mistake rather than as depth, and it is the first thing the eye finds.
    /// 54 with a 4pt block reaches 31 and clears the ring on every side — the hop below included.
    ///
    /// The three of them are one decision, which is what ``ringClearance`` is for.
    private static let faceDiameter: CGFloat = 54
    /// `box-shadow:0 6px 0 0` — a solid block under the face rather than a blur, which is what the design draws.
    private static let faceLift: CGFloat = 4
    /// `@keyframes breathe{50%{transform:translateY(-4px)}}` — how far the open face rises.
    private static let breathe: CGFloat = 4

    /// The gap between the face at its furthest travel and the inside of the ring. **Positive, or the face crosses
    /// its own ring** — which is the defect this exists to keep fixed.
    ///
    /// `nonisolated` and not `private` so `LearnViewTests` can assert it. Four constants that have to hold a
    /// relationship are not four constants; a test is the only thing that keeps them one.
    nonisolated static var ringClearance: CGFloat {
        // The stroke is centred on a circle inset by half its width, so its inner edge is a full width in.
        let ringInnerEdge = diameter / 2 - ringWidth
        let faceReach = faceDiameter / 2 + max(faceLift, breathe)
        return ringInnerEdge - faceReach
    }

    private var isLocked: Bool { node.state == .locked }

    var body: some View {
        Button(action: action) {
            ZStack {
                ring
                face
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .contentShape(.circle)
        }
        .buttonStyle(HWPressStyle())
        // One element for three drawn things. The title is the label because the caption under the node is
        // hidden, the server's sentence is the value, and the hint is what pressing it will do.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: node.title))
        .accessibilityValue(Text(verbatim: node.progressLabel))
        // **The `START` flag's reading lives here**, because the flag itself is hidden — see
        // `HWComponentCopy.lessonNextHint` for the build in which nothing said it at all.
        .accessibilityHint(Text(HWComponentCopy.lessonHint(state: node.state, isNext: node.isNext)))
    }

    /// `.ring` — one arc per question, lit up to `filledSegments`.
    ///
    /// Rotated so the first arc starts at the top, as `transform:rotate(-90deg)` does. The rotation is not
    /// mirrored under Arabic and is not meant to be: a progress ring fills clockwise in both directions of
    /// reading, and it encodes no direction to reverse (ADR-0011).
    private var ring: some View {
        ZStack {
            ForEach(0..<max(node.segments, 1), id: \.self) { index in
                arc(index)
                    .stroke(
                        index < node.filledSegments && !isLocked ? accent.base : trackColour,
                        style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round)
                    )
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(Self.ringWidth / 2)
    }

    private var trackColour: Color { theme.palette.feedback.lockedSoft }

    /// One arc of the ring, with the design's gap either side of it.
    private func arc(_ index: Int) -> some Shape {
        let segments = max(node.segments, 1)
        let slot = 1.0 / Double(segments)
        // `gap:7` over a 226pt circumference. Absent for a single-segment ring, which would otherwise be a
        // circle with a notch in it for no reason.
        let gap = segments > 1 ? 0.031 : 0
        return Circle().trim(from: Double(index) * slot + gap / 2, to: Double(index + 1) * slot - gap / 2)
    }

    /// `.face` — the tinted disc with the lesson's glyph, or the padlock.
    private var face: some View {
        ZStack {
            // The solid lift the design draws as a hard-edged shadow.
            Circle()
                .fill(isLocked ? theme.palette.feedback.locked : accent.deep)
                .frame(width: Self.faceDiameter, height: Self.faceDiameter)
                .offset(y: Self.faceLift)

            Circle()
                .fill(faceGround)
                .frame(width: Self.faceDiameter, height: Self.faceDiameter)
                .overlay {
                    Image(systemName: glyph)
                        .font(.hw(.subheading))
                        .foregroundStyle(faceInk)
                }
        }
        // `.node.current .face{animation:breathe 2.4s var(--ease-io) infinite}` — the face of the lesson that is
        // **open** rises and settles, so out of fifteen nodes the one the reader can start is the one that moves.
        // A finished face and a locked one are still: `.done` and `.locked` carry no such rule in the design, and
        // a map where everything moved would point at nothing.
        //
        // Applied to the face rather than to the node, exactly as the design's selector is: the ring stays put
        // while the disc inside it lifts, which is what makes the movement read as the face rising out of its own
        // shadow instead of the whole node sliding.
        .hwBreathes(suppressed: reduceMotion || node.state != .available)
        .accessibilityHidden(true)
    }

    /// `linear-gradient(155deg,var(--acc),var(--acc-deep))`, or the locked greys.
    private var faceGround: AnyShapeStyle {
        hwAccentGround(accent, isLocked: isLocked, lockedFill: theme.palette.feedback.lockedSoft)
    }

    private var faceInk: Color {
        isLocked ? theme.palette.surface.inkSecondary : theme.palette.brand.ink
    }

    /// The tick on a finished lesson, the padlock on a shut one, and the lesson's own glyph otherwise — which is
    /// exactly the design's `done ? check : open ? ICON[l.icon] : padlock`.
    ///
    /// The two state glyphs come from ``HWLessonRow/glyph(for:)`` rather than being written again here, so the
    /// path and the rows that replace it cannot come to disagree about what "finished" looks like — and so
    /// `LocalisationTests` has one table to subtract from the keys it reads out of the source.
    private var glyph: String {
        switch node.state {
        case .completed: HWLessonRow.glyph(for: .completed)
        case .available: node.systemImage
        case .locked: HWLessonRow.glyph(for: .locked)
        }
    }
}

/// The design's `.guide-item` — a numbered row carrying a lesson's title, a second line, and its state.
///
/// **Two callers, one shape.** It is the unit guide sheet's list, and it is what ``HWLessonTrack`` becomes at
/// accessibility sizes: both want a number, a title, a line of detail, and a status glyph, and a second component
/// would be the same row drawn twice.
struct HWLessonRow: View {
    @Environment(ThemeManager.self) private var theme

    /// The `.gi-n` chip's figure, already a string — spelled where it is computed, as everywhere else.
    private let number: String
    /// Server content.
    private let title: String
    /// Server content — the lesson's blurb in the sheet, its progress sentence in the replacement.
    private let detail: String
    private let state: HWLessonNodeState
    /// Whether this is the lesson to do next. It draws nothing — the `START` flag is the path's — and it is here
    /// for the **hint**, so that a reader who never sees the flag is told which lesson the cursor is on.
    private let isNext: Bool
    private let tint: HWUnitTint
    private let action: () -> Void

    init(
        number: String,
        title: String,
        detail: String,
        state: HWLessonNodeState,
        isNext: Bool = false,
        tint: HWUnitTint,
        action: @escaping () -> Void
    ) {
        self.number = number
        self.title = title
        self.detail = detail
        self.state = state
        self.isNext = isNext
        self.tint = tint
        self.action = action
    }

    private var accent: HWPalette.UnitAccent { theme.palette.units.accent(tint) }

    /// `.gi-s` — a tick when it is done, a star when it is open, a padlock when it is not.
    ///
    /// **The one table for the three state glyphs**, read by the node on the path as well. `nonisolated` and
    /// `static` for the reason `ExpensesView.symbol(_:)` is: `LocalisationTests` reads the source for dotted
    /// literals and cannot tell a symbol name returned from a `switch` from a catalogue key, so it asks the type
    /// for its glyphs and subtracts them. Exact, and it stays right when a glyph changes.
    nonisolated static func glyph(for state: HWLessonNodeState) -> String {
        switch state {
        case .completed: "checkmark"
        case .available: "star"
        case .locked: "lock.fill"
        }
    }

    /// The status glyph's colour — and `deep` rather than `base` for the open state, because an accent's base is
    /// a *fill* colour: `sun`'s is about 1.9:1 on a white card, under the 3:1 a non-text control needs. `deep`
    /// is the same accent, legible.
    private var statusInk: Color {
        switch state {
        case .completed: theme.palette.meter.reached
        case .available: accent.deep
        case .locked: theme.palette.feedback.locked
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // The design's `.gi-n` is `--acc-deep` on `--acc-soft`, which for `sun` is about 2.6:1. The wash
                // stays — it is what makes the chip the unit's — and the numeral takes the surface's own ink,
                // which clears 13:1 on every one of the five softs.
                Text(verbatim: number)
                    .font(.hw(.caption).weight(.heavy))
                    .foregroundStyle(theme.palette.surface.ink)
                    .monospacedDigit()
                    .frame(minWidth: 32, minHeight: 32)
                    .hwBox(fill: accent.soft, radius: .small)
                    // The row's own position says which number it is; reading it as well says it twice.
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.hw(.bodyLarge).weight(.bold))
                        .foregroundStyle(
                            state == .locked ? theme.palette.surface.inkSecondary
                                : theme.palette.surface.ink
                        )
                        .fixedSize(horizontal: false, vertical: true)

                    Text(verbatim: detail)
                        .font(.hw(.caption))
                        .foregroundStyle(theme.palette.surface.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: Self.glyph(for: state))
                    .font(.hw(.body))
                    .foregroundStyle(statusInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(minHeight: HWTouchTarget.minimum)
            .hwBox(
                fill: theme.palette.surface.raised,
                radius: .medium,
                border: theme.palette.surface.separator,
                elevation: .small
            )
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        // The status is a glyph, and a glyph reaches VoiceOver not at all — so the row's two strings are the
        // label and the value, and the hint says what pressing it does.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: detail))
        .accessibilityHint(Text(HWComponentCopy.lessonHint(state: state, isNext: isNext)))
    }
}

// MARK: - The map's ambient loops

/// A **continuous loop that is decoration rather than feedback** — the design's `breathe`, `bob`, and `orb`, which
/// are the three animations this screen runs forever.
///
/// One modifier for all three because they are one shape: a distance, a scale, a period, and the rule that
/// `prefers-reduced-motion` stops it. Three copies of a latched `@State` and a `repeatForever` would be three
/// places to forget the `.id(suppressed)` rebuild in — a note `LandingView`'s two ambient loops already carry
/// twice, which is what says the shape is worth naming here.
///
/// **Suppression here *removes* the loop rather than replacing it, and that is ADR-0012's rule rather than an
/// exception to it.** Replace-never-remove governs *feedback*: something the reader would otherwise not know had
/// happened. None of these three carry a fact. The **START** flag says which lesson is next in a word and reaches
/// VoiceOver through the node's hint; an open node's state is in its ring, its glyph, and its accessibility value;
/// the light in a unit band's corner says nothing at all. A reader who has asked for less movement loses no
/// information, which is the same finding `LandingView.ambientFloat` recorded for the hero card.
///
/// File-private on purpose. A design system earns a modifier when a second *screen* wants it, and until one does
/// these are the Learn map's.
private struct HWAmbientLoop: ViewModifier {
    /// How far it travels, in points. Negative is upward.
    let lift: CGFloat
    /// What it grows to at the far end. `1` for the two that only travel.
    let scale: CGFloat
    /// The period. Seconds rather than an ``HWDuration``, because an ambient loop is not a transition — see
    /// ``HWCurve/loop(seconds:)``, which exists to make that exception visible at the call site.
    let seconds: Double
    let suppressed: Bool

    @State private var atFarEnd = false

    func body(content: Content) -> some View {
        let moved = atFarEnd && !suppressed

        return content
            .offset(y: moved ? lift : 0)
            .scaleEffect(moved ? scale : 1)
            .animation(
                suppressed ? nil : HWMotion.easeInOut.loop(seconds: seconds).repeatForever(autoreverses: true),
                value: atFarEnd
            )
            .onAppear { atFarEnd = true }
            // Rebuilt when the setting changes, so turning Reduce Motion off starts the loop rather than waiting
            // for a relaunch: `.animation(_:value:)` has nothing left to fire on once `atFarEnd` has latched.
            .id(suppressed)
    }
}

private extension View {
    /// `@keyframes breathe` — an open lesson's face rising 4pt and settling, over 2.4s.
    func hwBreathes(suppressed: Bool) -> some View {
        modifier(HWAmbientLoop(lift: -4, scale: 1, seconds: 2.4, suppressed: suppressed))
    }

    /// `@keyframes bob` — the **START** flag hopping 5pt, over 1.6s.
    func hwBobs(suppressed: Bool) -> some View {
        modifier(HWAmbientLoop(lift: -5, scale: 1, seconds: 1.6, suppressed: suppressed))
    }

    /// `@keyframes orb` — the light in a unit band's corner drifting 12pt down and swelling to 1.16, over 9s.
    ///
    /// The design drifts it 14pt sideways as well; ``HWUnitHeader/bloom`` records why that half is dropped.
    func hwDrifts(suppressed: Bool) -> some View {
        modifier(HWAmbientLoop(lift: 12, scale: 1.16, seconds: 9, suppressed: suppressed))
    }
}

#if DEBUG
private let previewNodes: [HWLessonTrack.Node] = [
    .init(
        id: "u1l1",
        number: "1",
        title: "Gross vs. Net Income",
        progressLabel: "Completed, all 4 questions right",
        systemImage: "banknote",
        state: .completed,
        segments: 4,
        filledSegments: 4,
        isNext: false
    ),
    .init(
        id: "u1l2",
        number: "2",
        title: "The Time-Value of Money",
        progressLabel: "2 of 4 questions answered",
        systemImage: "clock",
        state: .available,
        segments: 4,
        filledSegments: 2,
        isNext: true
    ),
    .init(
        id: "u1l3",
        number: "3",
        title: "Needs vs. Wants",
        progressLabel: "Locked until you finish the lesson before it",
        systemImage: "shuffle",
        state: .locked,
        segments: 4,
        filledSegments: 0,
        isNext: false
    ),
]

@MainActor
private func previewUnit(unlocked: Bool = true) -> some View {
    VStack(spacing: 8) {
        HWUnitHeader(
            number: "1",
            caption: Text(verbatim: "UNIT 1 · INCOME & MINDSET"),
            title: "Build the Foundation",
            subtitle: "Income & Mindset",
            tint: .sun,
            isUnlocked: unlocked,
            onOpenGuide: {}
        )

        HWLessonTrack(tint: .sun, nodes: previewNodes, startLabel: "START") { _ in }
    }
}

#Preview("A unit — the header, the path, and its three node states") {
    ScrollView { previewUnit().padding(.horizontal, 18) }
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("A locked unit — the greys, and the ink that stays readable on them") {
    previewUnit(unlocked: false)
        .padding(.horizontal, 18)
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("Guide rows — the three states as the sheet lists them") {
    VStack(spacing: 8) {
        HWLessonRow(
            number: "1",
            title: "Gross vs. Net Income",
            detail: "Know what really lands in your bank account.",
            state: .completed,
            tint: .mint
        ) {}
        HWLessonRow(
            number: "2",
            title: "The Time-Value of Money",
            detail: "Why money loses power while it sits still.",
            state: .available,
            isNext: true,
            tint: .mint
        ) {}
        HWLessonRow(
            number: "3",
            title: "Needs vs. Wants",
            detail: "Sort your spending into two simple groups.",
            state: .locked,
            tint: .mint
        ) {}
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

/// Where the path stands aside and the same lessons become rows (ADR-0012).
#Preview("AX3 — the path is replaced by the same lessons as rows") {
    ScrollView { previewUnit().padding(.horizontal, 18) }
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("RTL — the path zig-zags the other way and the connectors follow") {
    ScrollView { previewUnit().padding(.horizontal, 18) }
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround())
        .hwTheme()
}
#endif
