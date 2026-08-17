import SwiftUI

/// Learn, converted from the design's `learn` document — **the unit map, the progress, and the way in**.
///
/// Five units, fifteen lessons, a segmented progress ring on each, and the per-unit guide sheet. Everything the
/// design worked out in the browser arrives instead: which lessons are open, which unit has been reached, which
/// lesson the **START** badge sits on, how many arcs each ring has and how many are lit, and every count said in
/// words (ADR-0020, ADR-0034).
///
/// **It is the one screen that reads two endpoints**, and that is invariant 8 deciding where the seam goes rather
/// than an exception to one-read-per-screen: the curriculum is the same 100 KB for everybody and carries an ETag,
/// while progress through it is per-user and bypasses every cache. The view model joins them by lesson id before
/// this file sees either (``LearnMap``).
///
/// **Sequential unlocking is rendered here and enforced there.** A locked node is drawn with a padlock and, when
/// pressed, says why — which is the design's own behaviour. Nothing about that decides anything: the server holds
/// the rule, so a client that got the lock wrong would refuse a lesson the next reload offers rather than granting
/// one nobody earned.
///
/// **The lesson player lands here** (#20). An open node opens it as a full-screen cover, which is what the design's
/// slide-up `.player` section is — so the closure the shell supplied while the player was unwritten has gone with the
/// screen it was standing in for (ADR-0034's "what this leaves"). The player is Learn's because a lesson is a modal
/// over the map rather than a tab or a pushed page.
struct LearnView: BaseView {
    @Environment(ThemeManager.self) private var theme

    /// Held rather than read from `@Environment`, so a test or a preview can construct the screen over a fixture
    /// transport. The five-tab shell puts one per tab in the environment.
    let viewModel: LearnViewModel

    /// Overridden because a curriculum that arrived with no units in it is `.empty`, and a screen with no empty
    /// copy would fall back to a default that says nothing about Learn.
    var stateCopy: StateCopy {
        StateCopy(empty: "learn.empty")
    }

    /// **The chrome, and the page is ``LearnMapPage``.**
    ///
    /// The split is the one ADR-0033 found by looking: `ImageRenderer` does not lay out the content of a
    /// `ScrollView`, so a render of the whole screen comes back as an empty ground — and a test asserting that it
    /// rendered passes on it. Everything the reader looks at is therefore in a view a test can photograph, and
    /// what is left here is the scroll, the sheet, and the toast.
    @ViewBuilder
    func loadedContent(_ map: LearnMap) -> some View {
        ScrollView {
            LearnMapPage(map: map, onOpenGuide: viewModel.openGuide(unitID:), onSelect: press)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The unit guide, opened with an **id** so a reload underneath re-renders the sheet from the new payload
        // rather than from the unit it was opened with (ADR-0020).
        //
        // **Presented off the id, not off the resolved unit.** Reading `openGuideUnit != nil` here meant a reload
        // that dropped the unit flipped presentation to `false` without any dismissal writing through — the id
        // stayed set, and the sheet re-presented itself the moment the unit came back. Review found it.
        .sheet(
            isPresented: Binding(
                get: { viewModel.isShowingGuide },
                set: { if !$0 { viewModel.closeGuide() } }
            )
        ) {
            if let unit = viewModel.openGuideUnit {
                guideSheet(unit)
            } else {
                // A unit that went away under an open sheet. An empty panel is worse than none, and closing is
                // the honest answer — the reader can open the one that is there.
                Color.clear.onAppear { viewModel.closeGuide() }
            }
        }
        // **The lesson player covers the screen**, which is what the design's slide-up section is: a lesson is a
        // focused mode, and a push inside the tab's stack would leave the tab bar under it. It is presented off the
        // *object* rather than off an id — unlike the guide sheet above — because the player holds a run, and a run
        // re-read from each reload would restart the lesson under the reader (``LessonPlayerViewModel``).
        .fullScreenCover(
            isPresented: Binding(
                get: { viewModel.player != nil },
                set: { if !$0 { viewModel.closePlayer() } }
            )
        ) {
            if let player = viewModel.player {
                LessonPlayerView(viewModel: player, onClose: viewModel.closePlayer)
            }
        }
        .hwToast(Self.copy(for: viewModel.notice), isPresented: viewModel.notice != nil)
        // The toast's lifetime is the screen's, not the component's (``HWToast``): it answers something the reader
        // just did, so it goes after a moment rather than waiting to be dismissed.
        .task(id: viewModel.notice) {
            guard viewModel.notice != nil else { return }
            try? await Task.sleep(for: .seconds(2.4))
            viewModel.dismissNotice()
        }
    }

    // MARK: - Pressing a lesson

    /// Start the lesson, or say why it will not start — **the screen's one branch**, so the node on the path and
    /// the row in the guide sheet cannot come to disagree about what a press does.
    ///
    /// It branches on the node's own state rather than on a second lookup, which is what makes the state the
    /// reader can see and the state that decides necessarily the same one. The refusal is the view model's, so it
    /// is the view model a test asks about.
    private func press(_ node: HWLessonTrack.Node) {
        if node.state == .locked {
            viewModel.refuseLockedLesson()
        } else {
            viewModel.openLesson(lessonID: node.id)
        }
    }

    // MARK: - The unit guide

    /// `.sheet` / `.guide-*` — the unit's blurb and its lessons in order.
    private func guideSheet(_ unit: LearnMap.Unit) -> some View {
        HWSheetChrome(title: "learn.guide.title", onClose: { viewModel.closeGuide() }) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Self.caption(for: unit.content)
                        .hwEyebrow()
                        .fixedSize(horizontal: false, vertical: true)

                    Text(verbatim: unit.content.title)
                        .font(.hw(.subheading))
                        .foregroundStyle(theme.palette.surface.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(verbatim: unit.content.blurb)
                        .font(.hw(.body))
                        .foregroundStyle(theme.palette.surface.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                HWSheetList {
                    ForEach(unit.lessons) { lesson in
                        HWLessonRow(
                            // **The lesson's own number**, not `index + 1`: the design numbers the sheet 1…n per
                            // unit, and a figure the reader sees comes from the payload (ADR-0020).
                            number: lesson.content.numberText,
                            title: lesson.content.title,
                            // The design's `.gi-b` is the lesson's blurb, which is what a reader deciding
                            // whether to start it wants. The progress sentence is on the node.
                            detail: lesson.content.blurb,
                            state: Self.state(lesson.progress.state),
                            isNext: lesson.isNext,
                            tint: Self.tint(unit.content.accent)
                        ) {
                            viewModel.closeGuide()
                            // Through the same mapping and the same branch the path uses, rather than a second
                            // reading of `isOpen` here.
                            press(Self.node(lesson))
                        }
                    }
                }
            }
        }
        // The design's panel is 78% of the screen and drag-dismissible, which is what a medium detent is.
        .presentationDetents([.medium, .large])
    }

    // MARK: - Mapping

    /// "Unit 3 · Debt & Credit" — the `.unit-cap` and the guide sheet's `.guide-cap`, which are the same string.
    ///
    /// One catalogue entry with **numbered** arguments rather than two pieces joined here: a language that wants
    /// the subtitle first has to be able to ask, and the separator belongs to the translation (ADR-0011).
    static func caption(for unit: Curriculum.Unit) -> Text {
        Text("learn.unit.caption \(unit.numberText) \(unit.subtitle)")
    }

    /// The five unit accents, from the payload's name to the palette's slot.
    ///
    /// A mapping rather than a shared type, for the reason `HomeView` maps `HomeScreen.Savings.Verdict` onto
    /// `HWSavingsMeter.Verdict`: the payload's vocabulary and the design system's are allowed to move apart, and
    /// the place they meet should be one function a test can call for every case.
    nonisolated static func tint(_ accent: Curriculum.Accent) -> HWUnitTint {
        switch accent {
        case .sun: .sun
        case .mint: .mint
        case .coral: .coral
        case .sky: .sky
        case .violet: .violet
        }
    }

    /// The three lesson states, from the payload's to the component's.
    nonisolated static func state(_ state: LearnScreen.LessonState) -> HWLessonNodeState {
        switch state {
        case .completed: .completed
        case .available: .available
        case .locked: .locked
        }
    }

    /// One mapped lesson as the track's own value.
    ///
    /// `static` and total, so the whole translation from payload to component is one function a test can hand
    /// every state to — and so a `body` does no mapping while it draws.
    nonisolated static func node(_ lesson: LearnMap.Lesson) -> HWLessonTrack.Node {
        HWLessonTrack.Node(
            id: lesson.id,
            number: lesson.content.numberText,
            title: lesson.content.title,
            progressLabel: lesson.progress.progressLabel,
            systemImage: symbol(lesson.content.icon),
            state: state(lesson.progress.state),
            segments: lesson.progress.segments,
            filledSegments: lesson.progress.filledSegments,
            isNext: lesson.isNext
        )
    }

    /// The design's fifteen lesson glyphs, as SF Symbols.
    ///
    /// `nonisolated` because `LocalisationTests` subtracts these from the localisation keys it finds in the source
    /// — the same trick it uses for `AppTab.systemImage` and `ExpensesView.symbol(_:)`. Most of them are dotted
    /// names and would otherwise read as catalogue keys with nothing behind them.
    ///
    /// Three are readings rather than transcriptions, and each says so. The design's fork for "needs vs. wants"
    /// becomes `shuffle` — a sorting gesture rather than a road that splits. Its balance scales become
    /// `plusminus`, because SF Symbols has no scales and "some borrowing helps you, some traps you" is the
    /// arithmetic the lesson is about. And its looping cash-flow arrow becomes `arrow.up.arrow.down`: money in and
    /// money out, said vertically so there is no direction to mirror (ADR-0011).
    nonisolated static func symbol(_ icon: Curriculum.Unit.Icon) -> String {
        switch icon {
        case .wallet: "banknote"
        case .clock: "clock"
        case .split: "shuffle"
        case .flow: "arrow.up.arrow.down"
        case .pie: "chart.pie"
        case .shield: "checkmark.shield"
        case .bank: "building.columns"
        case .gauge: "speedometer"
        case .scales: "plusminus"
        case .steps: "stairs"
        case .umbrella: "umbrella"
        case .lock: "lock.shield"
        case .spark: "sparkles"
        case .layers: "square.stack"
        case .grid: "square.grid.2x2"
        case .book: "book"
        }
    }

    /// Which sentence the toast shows. **The choice is the view model's and the words are the catalogue's**, the
    /// split `ExpensesView.copy(for:)` draws for the same reason.
    static func copy(for notice: LearnViewModel.Notice?) -> LocalizedStringResource? {
        switch notice {
        case .lessonLocked: "learn.notice.locked"
        case nil: nil
        }
    }
}

/// Everything on the Learn screen the reader looks at: the stats bar, then the five units and their paths.
///
/// **Separate from ``LearnView`` because `ImageRenderer` does not lay out the content of a `ScrollView`**, which
/// ADR-0033 found the hard way — a render of the whole screen comes back as an empty ground, and a test asserting
/// that it rendered passes on it. `LearnViewTests` photographs this and asserts that two different payloads produce
/// two different pictures, which is the assertion an empty ground cannot pass.
///
/// It holds no view model, deliberately: it takes the map it draws and two closures. So it is a *page* rather than a
/// screen — nothing in it can fetch, and a test can render it without a transport.
struct LearnMapPage: View {
    let map: LearnMap
    /// `.unit-guide` — opens the sheet listing a unit's lessons.
    let onOpenGuide: (String) -> Void
    /// Pressing a node. The **branch lives in `LearnView`** so that the path and the guide sheet share one.
    let onSelect: (HWLessonTrack.Node) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            statsBar

            ForEach(map.units) { unit in
                self.unit(unit)
            }
        }
    }

    /// `.stats` — the mark, the streak, and the XP, on **one row**.
    ///
    /// **The design has no title on this screen and now neither does this.** An earlier build put a full `HWTopBar`
    /// above the figures, on the reading that the other four tab roots carry one and that a screen with no heading
    /// gives VoiceOver's heading rotor nothing to land on (ADR-0012). The first half was a guess and the second is
    /// answered more cheaply: the design puts its `.mark` *in* the stats row rather than over a title, and this row
    /// is the heading — it carries the trait and reads "Learn", so the rotor lands on it without a title line the
    /// design does not draw. `learn.eyebrow` went with it.
    ///
    /// The row is a `.contain` element rather than a `.combine`, because the two chips are figures a reader wants
    /// to hear one at a time and each already composes its own sentence server-side (``HWStatChip``).
    private var statsBar: some View {
        HStack(spacing: 8) {
            // `surface`, because Learn is one of the five light screens — the galaxy tile is Landing's (``HWMark``).
            HWMark(size: 34, appearance: .surface)

            HWStatChip(
                tone: .streak,
                value: map.progress.streak.display,
                accessibilityLabel: map.progress.streak.accessibilityLabel
            )

            Spacer(minLength: 0)

            HWStatChip(
                tone: .experience,
                value: map.progress.xp.display,
                accessibilityLabel: map.progress.xp.accessibilityLabel
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("learn.title"))
        .accessibilityAddTraits(.isHeader)
    }

    /// `.unit` — the header band, then the path of nodes under it.
    private func unit(_ unit: LearnMap.Unit) -> some View {
        VStack(spacing: 8) {
            HWUnitHeader(
                number: unit.content.numberText,
                caption: LearnView.caption(for: unit.content),
                title: unit.content.title,
                subtitle: unit.content.subtitle,
                tint: LearnView.tint(unit.content.accent),
                isUnlocked: unit.isUnlocked
            ) {
                onOpenGuide(unit.id)
            }

            HWLessonTrack(
                tint: LearnView.tint(unit.content.accent),
                nodes: unit.lessons.map(LearnView.node),
                startLabel: "learn.start",
                onSelect: onSelect
            )
        }
        // One container per unit, so VoiceOver's container gestures move between units rather than through fifteen
        // nodes in a row.
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Learn — two lessons done and a third part-answered") {
    NavigationStack { LearnView(viewModel: .previewInProgress) }.hwTheme()
}

#Preview("Learn — a brand-new account, one lesson open") {
    NavigationStack { LearnView(viewModel: .previewFirstRun) }.hwTheme()
}

#Preview("Learn — every lesson finished, so no START badge anywhere") {
    NavigationStack { LearnView(viewModel: .previewComplete) }.hwTheme()
}

#Preview("Learn — offline") {
    NavigationStack { LearnView(viewModel: .previewOffline) }.hwTheme()
}

#Preview("Learn — the endpoint is not written yet (501)") {
    NavigationStack { LearnView(viewModel: .previewNotImplemented) }.hwTheme()
}

#Preview("Learn — Arabic, right to left") {
    NavigationStack { LearnView(viewModel: .previewInProgress) }
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

/// Where the zig-zagging path stands aside and the same lessons become rows (ADR-0012).
#Preview("Learn — AX5") {
    NavigationStack { LearnView(viewModel: .previewInProgress) }
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
