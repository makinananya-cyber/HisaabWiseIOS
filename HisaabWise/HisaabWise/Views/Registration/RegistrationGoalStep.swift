import SwiftUI

/// Step 3 of registration — the design's `view-reg3`, "set up your goals".
///
/// The 20% statement, one number, and the two ways to leave: **Submit** with what is in the box, or **Skip for
/// now** with the suggestion. Either one is the atomic `POST /v1/auth/register` that creates the account.
///
/// **Skip is not "no goal".** The design's own `finish(suggested(), true)` sets the goal to 20% and marks it
/// `auto-20-percent`; skipping means "you choose for me", not "leave it empty". Which is why the request carries
/// `goalWasSkipped` — a skipped 20% and a typed 20% are the same figure and different facts, and only the app
/// that offered the choice can tell them apart (#15).
///
/// **The percentage under the box is the one figure the client computes, and it is not money.** ADR-0003 gives
/// every converted or formatted *monetary* value to the server; this is a ratio between two numbers the user typed
/// on this screen, neither of which has reached a server yet. Everything that comes *back* — including this goal,
/// once the account exists — is the server's to format.
struct RegistrationGoalStep: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let viewModel: RegistrationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statement.hwEnters(step: 3, suppressed: reduceMotion)

            goalField.hwEnters(step: 4, suppressed: reduceMotion)

            if viewModel.suggestsUsingTheSuggestion {
                useSuggestion
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            if let hint = Self.hint(for: viewModel) {
                Text(hint)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.brand.inkSecondary)
                    .opacity(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            submit.hwEnters(step: 5, suppressed: reduceMotion)

            skip.hwEnters(step: 5, suppressed: reduceMotion)

            if let failure = viewModel.formFailure {
                formFailure(failure)
            }
        }
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: viewModel.goalText)
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: viewModel.failures)
    }

    /// `.statement` — the glass card that explains the 20% rule and shows what it comes to.
    ///
    /// The design animates an `.orb` behind it on a 9-second loop. It is not drawn: an ambient loop needs a
    /// Reduce Motion replacement and a reason, and a decorative blur behind a card the user reads once has
    /// neither — the same call `HWBrandGround` made about the design's drifting starfield.
    private var statement: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("registration.three.rule.eyebrow")
                .hwEyebrow(.brand)
                .fixedSize(horizontal: false, vertical: true)

            Text("registration.three.rule.body")
                .font(.hw(.body))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // `.st-amount` — the symbol, the figure, and "a month", on one baseline.
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(verbatim: viewModel.currency?.symbol ?? "")
                    .font(.hw(.subheading))
                    .foregroundStyle(theme.palette.brand.inkAccent)

                Text(verbatim: viewModel.suggestedGoalText ?? "")
                    .font(.hw(.display))
                    .foregroundStyle(theme.palette.brand.ink)
                    .tracking(-1.2)

                Text("registration.three.perMonth")
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.brand.inkSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 5)
            // The three parts are one figure, read as one thing: "AED 1,600 a month" rather than three
            // fragments a listener has to reassemble (ADR-0012).
            .accessibilityElement(children: .combine)

            Text("registration.three.rule.footer")
                .font(.hw(.caption))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .opacity(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .hwBox(
            // `linear-gradient(150deg,rgba(sky,.16),rgba(planetary,.22))` — the design's glass card, as the two
            // raised brand roles rather than two alphas of a palette name (ADR-0001).
            fill: theme.palette.brand.raised,
            radius: .extraLarge,
            border: theme.palette.brand.separatorStrong
        )
        .accessibilityElement(children: .contain)
    }

    private var goalField: some View {
        HWMoneyField(
            "registration.three.goal.label",
            text: Binding(
                get: { viewModel.goalText },
                // Through the view model, because typing here is what makes the figure the *user's* rather than
                // the app's suggestion — and that distinction is what stops a corrected salary leaving a stale
                // goal behind (`goalIsSuggestion`).
                set: { viewModel.editGoal($0) }
            ),
            symbol: viewModel.currency?.symbol ?? "",
            code: viewModel.currency?.code ?? "",
            error: RegistrationView.copy(for: viewModel.failure(for: .goal))
        )
    }

    /// `.suggest` — offered only when the box holds something *other* than the suggestion, as the design's
    /// `useBtn.hidden = typed === s` does. A button that sets a field to what it already says is a button that
    /// does nothing.
    private var useSuggestion: some View {
        HWButton("registration.three.useSuggested", variant: .ghost, appearance: .brand, systemImage: "checkmark") {
            viewModel.useSuggestedGoal()
        }
    }

    private var submit: some View {
        HWButton(
            "registration.three.action",
            appearance: .brand,
            systemImage: "arrow.forward",
            state: viewModel.isSubmitting ? .inFlight : .ready
        ) {
            Task { await viewModel.submit() }
        }
        .background {
            Capsule()
                .fill(theme.palette.brand.inkAccent)
                .blur(radius: 24)
                .opacity(0.5)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
    }

    /// `#skip-goal` — "Skip for now", which submits the suggestion rather than nothing.
    private var skip: some View {
        HWButton(
            "registration.three.skip",
            variant: .quiet,
            appearance: .brand,
            state: viewModel.isSubmitting ? .inFlight : .ready
        ) {
            Task { await viewModel.skipGoal() }
        }
        .frame(maxWidth: .infinity)
    }

    /// The failures that belong to the form as a whole: offline, and whatever else the server said.
    ///
    /// An email collision is **not** drawn here — `submit()` sends the user back to step 1 with the field marked,
    /// because that is where it can be fixed (#15).
    private func formFailure(_ failure: RegistrationFailure) -> some View {
        Text(RegistrationView.copy(for: failure) ?? ErrorCopy.generic)
            .font(.hw(.body))
            .foregroundStyle(theme.palette.brand.danger)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Copy

    /// `#goal-hint` — what the typed figure comes to as a share of the salary, and how that reads against the
    /// rule.
    ///
    /// Four sentences rather than one assembled from a verdict and a number: the design writes "— right on the
    /// rule", "— ahead of the 20% rule. Nice.", and "— a little under the 20% rule, but a start is a start." as
    /// three different endings, and each is a whole sentence in the catalogue so a translation can put the
    /// percentage wherever its grammar wants it (ADR-0011).
    static func hint(for viewModel: RegistrationViewModel) -> LocalizedStringResource? {
        guard let share = viewModel.goalShareText, let comparison = viewModel.goalAgainstSuggestion else {
            // Nothing typed: the design points at Skip, which is the one control that needs no number.
            return "registration.three.hint.empty"
        }

        return switch comparison {
        case .orderedSame: "registration.three.hint.onTarget \(share)"
        case .orderedDescending: "registration.three.hint.above \(share)"
        case .orderedAscending: "registration.three.hint.below \(share)"
        }
    }
}

#if DEBUG
#Preview("Step 3 — pre-filled at the suggestion") {
    RegistrationStepPreview { RegistrationGoalStep(viewModel: .previewOnStepThree) }
}

#Preview("Step 3 — ahead of the rule") {
    RegistrationStepPreview { RegistrationGoalStep(viewModel: .previewGoalAboveTheRule) }
}

#Preview("Step 3 — under the rule, and the suggestion offered") {
    RegistrationStepPreview { RegistrationGoalStep(viewModel: .previewGoalBelowTheRule) }
}

#Preview("Step 3 — the box emptied") {
    RegistrationStepPreview { RegistrationGoalStep(viewModel: .previewGoalEmpty) }
}

#Preview("AX3 — the statement and the figure grow") {
    RegistrationStepPreview { RegistrationGoalStep(viewModel: .previewOnStepThree) }
        .dynamicTypeSize(.accessibility3)
}

#Preview("RTL") {
    RegistrationStepPreview { RegistrationGoalStep(viewModel: .previewGoalBelowTheRule) }
        .environment(\.layoutDirection, .rightToLeft)
}
#endif
