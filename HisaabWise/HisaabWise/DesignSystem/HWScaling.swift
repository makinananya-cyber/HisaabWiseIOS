import SwiftUI

/// How far text is allowed to grow, and what happens when growing stops being the answer.
///
/// ADR-0012 splits Dynamic Type in two, and the split is the whole decision:
///
/// - **Reading content scales unclamped, to AX5.** Tips, articles, and lesson steps *are* the education
///   product; clamping them is the real accessibility failure. Clamping a chart label is a cosmetic one.
///   Nothing in the app clamps text, and `AccessibilityTests` asserts that the range form of
///   `dynamicTypeSize` appears in this file and nowhere else.
/// - **The four data visualisations are replaced, not shrunk.** The donut's centre readout, the savings
///   meter's pin and percentage pill, the four-segment split bar, and the seven-day week strip are
///   fixed-layout in the design and break at AX5. Above the threshold each is swapped for a layout made of
///   text — a category list, a vertical list, a wrapping strip — which then scales like everything else.
///
/// This type holds the two numbers; ``SwiftUI/View/hwVisualisation(replacedBy:)`` is how a screen consumes
/// them.
enum HWScaling {
    /// The largest size a data visualisation is drawn at.
    ///
    /// It is `xxxLarge` because that is the largest **ordinary** size — the one immediately below the
    /// accessibility sizes, where ``replacesVisualisation(at:)`` takes over. The two have to meet exactly,
    /// and `ScalingTests` pins the join: a gap would leave sizes where the chart is capped and no
    /// alternative has replaced it, which is the shrunk chart ADR-0012 rules out.
    static let visualisationCeiling: DynamicTypeSize = .xxxLarge

    /// Whether a visualisation should stand aside for its alternative layout at this size.
    ///
    /// `isAccessibilitySize` rather than a hand-written comparison, because the boundary belongs to the
    /// platform: it is where the user has stopped asking for larger text and started asking for a layout
    /// that can carry it.
    static func replacesVisualisation(at size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }
}

extension View {
    /// Pairs a data visualisation with the equivalent layout that **replaces** it at accessibility sizes.
    ///
    /// The pattern the donut, savings meter, split bar, and week strip consume (ADR-0012). Below the
    /// threshold the chart is drawn, capped at ``HWScaling/visualisationCeiling`` — a cap that cannot bind
    /// while the threshold sits immediately above it, and that is deliberate: see the note at the clamp
    /// itself. At and above the threshold the chart is gone and `alternative` is what the screen shows. Not
    /// smaller — gone: a donut at 310% type is a circle with three overlapping labels in it, and shrinking
    /// the labels to fit is how a screen opts out of Dynamic Type while appearing to support it.
    ///
    /// **The alternative does double duty, and that is deliberate.** While the chart is on screen the same
    /// view is installed as its `accessibilityRepresentation`, so VoiceOver reads the list whether or not
    /// the list is what is drawn. One argument, one thing to write, and no way for a screen to supply an
    /// alternative layout and forget the ADR's other requirement — that a chart is readable at all.
    ///
    /// The alternative itself is **not** clamped: it is made of text, so it scales the whole way to AX5.
    ///
    /// ```swift
    /// HWDonut(slices: budget.categories)
    ///     .hwVisualisation {
    ///         HWCategoryList(budget.categories)   // the same figures, as rows
    ///     }
    /// ```
    /// - Parameter describesItself: whether the visualisation already publishes descriptors VoiceOver can read,
    ///   in which case the alternative is **not** installed as its representation below the threshold.
    ///
    ///   `false` for everything hand-built — a gradient with a pin on it has nothing a screen reader can do with
    ///   it, so the list has to stand in. `true` for a Swift Charts view, where every `SectorMark` carries its own
    ///   label and value: installing a representation there *replaces* those descriptors, so they are read by
    ///   nothing at any size — below the threshold the representation supersedes them and above it the chart is not
    ///   drawn. Which made ADR-0016's stated reason for choosing Swift Charts over a hand-rolled ring unrealised,
    ///   and is what this parameter exists to fix.
    func hwVisualisation<Alternative: View>(
        describesItself: Bool = false,
        @ViewBuilder replacedBy alternative: @escaping () -> Alternative
    ) -> some View {
        modifier(HWVisualisationScaling(describesItself: describesItself, alternative: alternative))
    }
}

/// The clamp, the swap, and the VoiceOver representation — the three things every visualisation would
/// otherwise decide for itself.
///
/// A `ViewModifier` rather than a container view so that the call site reads as a property of the chart
/// (`donut.hwVisualisation { … }`) instead of as a wrapper somebody can forget to wrap it in.
struct HWVisualisationScaling<Alternative: View>: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size

    /// Whether the content already has descriptors of its own — see `hwVisualisation(describesItself:replacedBy:)`.
    let describesItself: Bool

    @ViewBuilder let alternative: () -> Alternative

    func body(content: Content) -> some View {
        if HWScaling.replacesVisualisation(at: size) {
            alternative()
        } else {
            content
                // **This clamp cannot bind today, and it is here on purpose.** The threshold above sits
                // immediately over the ceiling, so anything reaching this branch is already at or below it.
                // What the line states is the largest size a chart may be *drawn* at, independently of where
                // the threshold happens to be — so moving the threshold later cannot silently un-cap the
                // chart. `ScalingTests` pins the join the two make; ADR-0025 records the redundancy.
                .dynamicTypeSize(...HWScaling.visualisationCeiling)
                // What VoiceOver reads while the chart is the thing on screen — **unless the chart says it
                // already has descriptors**. A hand-built shape has none, so the list stands in; a `SectorMark`
                // publishes a label and a value per slice, and installing a representation over it means those
                // descriptors are read by nothing at any size.
                .accessibilityRepresentation {
                    if describesItself {
                        content
                    } else {
                        alternative()
                    }
                }
        }
    }
}

#if DEBUG
/// The pattern with something recognisable in it: a ring with a figure at its centre, and the same figures
/// as rows.
private struct ScalingPreview: View {
    @Environment(ThemeManager.self) private var theme

    private let slices: [(name: String, share: String)] = [
        ("Rent", "40%"), ("Groceries", "25%"), ("Transport", "20%"), ("Other", "15%"),
    ]

    var body: some View {
        donut.hwVisualisation(replacedBy: { list })
            .padding()
    }

    private var donut: some View {
        ZStack {
            Circle()
                .stroke(theme.palette.categories.rent, lineWidth: 26)
                .frame(width: 150, height: 150)
            Text(verbatim: "AED 4,200")
                .font(.hw(.heading))
                .foregroundStyle(theme.palette.surface.ink)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(slices, id: \.name) { slice in
                HStack {
                    Text(verbatim: slice.name)
                    Spacer()
                    Text(verbatim: slice.share)
                }
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.ink)
            }
        }
    }
}

#Preview("The chart, at an ordinary size") {
    ScalingPreview().hwTheme()
}

#Preview("AX3 — the chart is replaced by the same figures as rows") {
    ScalingPreview()
        .dynamicTypeSize(.accessibility3)
        .hwTheme()
}

#Preview("AX5 — and the replacement keeps growing") {
    ScalingPreview()
        .dynamicTypeSize(.accessibility5)
        .hwTheme()
}

#Preview("RTL") {
    ScalingPreview()
        .environment(\.layoutDirection, .rightToLeft)
        .hwTheme()
}
#endif
