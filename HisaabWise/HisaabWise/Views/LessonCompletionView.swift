import SwiftUI

/// The celebration, converted from the design's `.cheer` section — **and the screen whose data is the submission**
/// (#20, ADR-0020).
///
/// **A `BaseView` whose one request is a `POST`.** Finishing the lesson submits the per-question results and this
/// screen draws what comes back (``LessonCompletionViewModel``), which is what the write rule already says: a write
/// answers with the payload the screen renders. Three of the ticket's requirements are that decision rather than
/// anything written here:
///
/// - **No connection is `LoadState.offline`, with a retry and nothing queued** (ADR-0019). The chrome draws it and
///   the CTA is the reader's; there is no drain, no pending badge, and no second attempt they did not ask for.
/// - **A `422` is a definite failure**, carrying its code through `ErrorCopy` — the server refusing an impossible
///   submission (invariant 10).
/// - **Every figure is read.** The XP earned, the accuracy, and the streak come from the response; the client held
///   the results it submitted and is not allowed to add them up.
///
/// **It takes no unit accent, and that is the design read carefully rather than a shortcut.** The design sets
/// `#done.className = 'cheer u-' + accent`, and *nothing inside reads it*: the badge is the sun gradient
/// (`linear-gradient(150deg,var(--sun),#E09A0C)`), the Continue button is mint (`.btn-ok`), and the three tiles are
/// fixed colours. A `tint` parameter was threaded in here and read by nothing until review noticed — the same shape as
/// `.stat--crown`, which is in the stylesheet and rendered by no one.
///
/// **Confetti and the badge's spring are suppressed under Reduce Motion, and the announcement is what replaces
/// them** (ADR-0012). The XP figure is on screen as text either way, which is the ADR's own instruction — "confetti
/// → a static celebratory badge carrying the XP figure" — and the announcement is the only form of it a VoiceOver
/// user ever gets.
struct LessonCompletionView: BaseView {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.locale) private var locale

    /// Whether the celebration has arrived, which is what the haptic fires on.
    ///
    /// **A `sensoryFeedback` trigger has to *change*.** Triggering on the XP figure looked right and never played:
    /// this content is built only once the submission has landed, so the figure's first value is also its only one
    /// and nothing ever transitions. This flips false → true when the screen appears, which is the event — the
    /// lesson counting, not the last step being tapped.
    @State private var hasLanded = false

    let viewModel: LessonCompletionViewModel

    /// **Continue** — back to the map. The caller's, because this screen does not own the one it covers.
    let onContinue: () -> Void

    /// Supplied even though the payload cannot be empty, because a server can answer with no completion at all and a
    /// screen with no empty copy falls back to a default that says nothing about Learn.
    var stateCopy: StateCopy {
        StateCopy(empty: "learn.completion.empty")
    }

    @ViewBuilder
    func loadedContent(_ completion: LessonCompletion) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                HWDoneBadge()

                headline(completion)

                stats(completion)

                HWWeekStrip(days: Self.week(completion.week))

                HWRunButton("learn.completion.continue", tone: .right, action: onContinue)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 26)
            .padding(.vertical, 30)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The falling paper, over everything and touching nothing. It draws itself as nothing under Reduce Motion —
        // see the note on ``HWConfetti`` for what stands in its place.
        .overlay { HWConfetti() }
        // `.success` on a finished lesson (ADR-0012). It fires on the *response*, not on the last step: what is
        // being confirmed is that the lesson counted, and until the submission lands nothing has.
        .sensoryFeedback(.success, trigger: hasLanded)
        // **The announcement, which is the confetti's replacement and the only reading a VoiceOver user gets.** The
        // three figures are on screen as text, but a celebration appearing where a question used to be is not an
        // event as far as VoiceOver is concerned (ADR-0012).
        .task(id: completion.xpEarned.display) {
            HWAnnouncement.post(
                "learn.completion.announcement \(completion.xpEarned.accessibilityLabel) \(completion.accuracy.accessibilityLabel)",
                in: locale,
                priority: .immediate
            )
            hasLanded = true
        }
    }

    /// `#done-h` and `#done-p` — what happened, and what it means for the streak.
    ///
    /// **The headline turns on the payload's own flag** (defect D13): a lesson run again says so, because the XP tile
    /// beside it reads `0` and a reader is owed the reason. The sentence under it is the server's, because it is a
    /// count with a plural in it (``LessonCompletion/streakLine``).
    private func headline(_ completion: LessonCompletion) -> some View {
        VStack(spacing: 8) {
            Text(completion.isFirstCompletion ? "learn.completion.title" : "learn.completion.title.again")
                .font(.hw(.title))
                .foregroundStyle(theme.palette.surface.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(verbatim: completion.streakLine)
                .font(.hw(.bodyLarge))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// `.done-stats` — the three tiles. **Above the accessibility threshold they become a column**, because three
    /// tiles in a row broke `+1,500` across three lines on the same reasoning `HWSpendSummary` records — reading the
    /// size to choose a *layout* is not clamping (ADR-0012).
    private func stats(_ completion: LessonCompletion) -> some View {
        HWCompletionStats {
            HWCompletionStat(
                tone: .experience,
                value: completion.xpEarned.display,
                caption: "learn.completion.xp",
                accessibilityLabel: completion.xpEarned.accessibilityLabel
            )
            HWCompletionStat(
                tone: .accuracy,
                value: completion.accuracy.display,
                caption: "learn.completion.accuracy",
                accessibilityLabel: completion.accuracy.accessibilityLabel
            )
            HWCompletionStat(
                tone: .streak,
                value: completion.screen.streak.display,
                caption: "learn.completion.streak",
                accessibilityLabel: completion.screen.streak.accessibilityLabel
            )
        }
    }

    /// The payload's week, as the component draws it. A mapping rather than a shared type, the same reason
    /// `LearnView.tint(_:)` is one: the payload's vocabulary and the design system's are allowed to move apart, and
    /// the place they meet should be one function a test can call.
    nonisolated static func week(_ days: [LessonCompletion.Day]) -> [HWWeekStrip.Day] {
        days.map {
            HWWeekStrip.Day(
                label: $0.label,
                isComplete: $0.isComplete,
                isToday: $0.isToday,
                accessibilityLabel: $0.accessibilityLabel
            )
        }
    }
}

#if DEBUG
#Preview("The celebration — a first completion") {
    LessonCompletionView(viewModel: .previewCompleted, onContinue: {}).hwTheme()
}

#Preview("The celebration — a replay, which earns nothing") {
    LessonCompletionView(viewModel: .previewRevisited, onContinue: {}).hwTheme()
}

#Preview("The celebration — no connection, so nothing counted yet") {
    LessonCompletionView(viewModel: .previewOffline, onContinue: {}).hwTheme()
}

#Preview("The celebration — the server refused the submission") {
    LessonCompletionView(viewModel: .previewRefused, onContinue: {}).hwTheme()
}

#Preview("The celebration — Arabic, right to left") {
    LessonCompletionView(viewModel: .previewCompleted, onContinue: {})
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

/// Where the week strip stands aside and the same seven days become rows (ADR-0012).
#Preview("The celebration — AX5") {
    LessonCompletionView(viewModel: .previewCompleted, onContinue: {})
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
