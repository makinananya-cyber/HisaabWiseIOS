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
        .hwBox(fill: ground, radius: .extraLarge, elevation: isUnlocked ? .medium : .small)
        .accessibilityElement(children: .contain)
    }
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
struct HWLessonTrack: View {
    @Environment(ThemeManager.self) private var theme

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

    /// Each node's centre in the track's own space, measured after layout.
    @State private var centres: [String: CGPoint] = [:]

    /// And the bottom of each node's whole **column** — the node, its label, and its badge.
    ///
    /// Measured separately because a connector that left a node's centre going straight down ran through the
    /// label underneath it, which is the collision the design's rotate-and-bow arithmetic exists to avoid. A
    /// curve leaving the column instead avoids it by construction, and it needs one more number rather than a
    /// second geometry model. **Looking at it running is what found this** — the first build drew a dotted line
    /// through the middle of "Emergency Fund".
    @State private var columnBottoms: [String: CGFloat] = [:]

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
        .padding(.vertical, 8)
    }

    private func nodeColumn(_ node: Node, isLeading: Bool) -> some View {
        VStack(spacing: 6) {
            if node.isNext {
                startBadge
            }

            HWLessonNode(node: node, tint: tint) { onSelect(node) }
                .onGeometryChange(for: CGPoint.self) { proxy in
                    let frame = proxy.frame(in: .named(Self.space))
                    return CGPoint(x: frame.midX, y: frame.midY)
                } action: { centres[node.id] = $0 }

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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named(Self.space)).maxY
        } action: { columnBottoms[node.id] = $0 }
    }

    /// `.start` — the bobbing "START" flag above the cursor.
    ///
    /// **It does not bob.** The design animates it on a 1.6s loop; ADR-0012's rule is replace-never-remove, and
    /// the replacement for a continuous attention loop is the thing itself — a bordered flag in the unit's accent
    /// is already the loudest element on the screen. Dropping the loop rather than gating it on Reduce Motion is
    /// what keeps this component out of the "animates without offering a replacement" shape.
    private var startBadge: some View {
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
        .accessibilityHidden(true)
    }

    /// `stroke-dasharray:2 15` at `stroke-width:4.5`, round caps — a line of dots rather than dashes.
    private static let stroke = StrokeStyle(lineWidth: 4.5, lineCap: .round, dash: [2, 15])

    /// The curves whose pair passes `include`.
    ///
    /// A **cubic** leaving one column at its bottom and entering the next node from straight above, so it sweeps
    /// past the label rather than through it — which is what the design's rotate-and-bow arithmetic achieves by a
    /// longer route. It needs no direction of its own, because both endpoints are measured.
    private func curves(_ include: (Link) -> Bool) -> Path {
        Path { path in
            for link in links where include(link) {
                guard link.to.y > link.from.y else { continue }
                // Both control points sit on the waist, which keeps the curve leaving and arriving vertically —
                // straight out of the column and straight into the ring above the next node.
                let waist = (link.from.y + link.to.y) / 2
                path.move(to: link.from)
                path.addCurve(
                    to: link.to,
                    control1: CGPoint(x: link.from.x, y: waist),
                    control2: CGPoint(x: link.to.x, y: waist)
                )
            }
        }
    }

    /// One connector: where it leaves, where it arrives, and whether the lesson it leaves is finished.
    private struct Link {
        let from: CGPoint
        let to: CGPoint
        let isDone: Bool
    }

    /// The pairs that have both ends measured. Before the first layout pass there are none, and drawing nothing
    /// is right — a curve to a node whose position is not known yet would be a line to the origin.
    ///
    /// It leaves from **below the label** and arrives at the top of the next **ring**, which is the asymmetry the
    /// label collision required: a node's own label is under it, and the next node's is under *that*.
    private var links: [Link] {
        zip(nodes, nodes.dropFirst()).compactMap { above, below in
            guard let from = centres[above.id],
                  let bottom = columnBottoms[above.id],
                  let to = centres[below.id]
            else { return nil }
            return Link(
                from: CGPoint(x: from.x, y: bottom),
                // The **node's own** diameter, read from the node rather than restated here: the curve landing on
                // the top of the ring is only correct while the two agree, and two 78s in one file agree until
                // somebody changes one of them.
                to: CGPoint(x: to.x, y: to.y - HWLessonNode.diameter / 2),
                isDone: above.state == .completed
            )
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
private struct HWLessonNode: View {
    @Environment(ThemeManager.self) private var theme

    let node: HWLessonTrack.Node
    let tint: HWUnitTint
    let action: () -> Void

    private var accent: HWPalette.UnitAccent { theme.palette.units.accent(tint) }

    /// `.node{width:78px;height:78px}` and `.face{width:58px}`.
    ///
    /// ``diameter`` is not `private`: the track reads it to know where a connector has to stop, and a second copy
    /// of 78 in the same file is two numbers that agree until one of them changes.
    static let diameter: CGFloat = 78
    private static let faceDiameter: CGFloat = 58
    /// `.ring circle{stroke-width:6}`.
    private static let ringWidth: CGFloat = 6
    /// `box-shadow:0 6px 0 0` — a solid block under the face rather than a blur, which is what the design draws.
    private static let faceLift: CGFloat = 5

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
