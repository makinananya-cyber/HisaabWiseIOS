import SwiftUI

/// The design's `.card` — the white, hairline-bordered, softly raised box almost every screen is made of.
///
/// Three slots, taken straight from the CSS: a `.card-cap` caption, a `.card-sub` subtitle, and the
/// content. The caption and the subtitle are not stacked — they are the two ends of `.card-top`, a
/// baseline-aligned row, which is why they are one row here and not two properties that happen to be
/// adjacent.
///
/// The subtitle is a `Text` rather than a `LocalizedStringResource` because it is usually a server
/// string — "12 expenses", "of ₹65,000" — and a component that insisted on a catalogue key would force
/// the caller to launder one (ADR-0003, ADR-0020).
struct HWCard<Content: View>: View {
    @Environment(ThemeManager.self) private var theme

    private let caption: LocalizedStringResource?
    private let subtitle: Text?
    private let content: Content

    init(
        caption: LocalizedStringResource? = nil,
        subtitle: Text? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.caption = caption
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if caption != nil || subtitle != nil {
                top
            }
            content
        }
        // `.card{padding:18px 16px}`
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hwBox(
            fill: theme.palette.surface.raised,
            radius: .extraLarge,
            border: theme.palette.surface.separator,
            elevation: .small
        )
        // One container per card, so VoiceOver reads a card as a card rather than as loose text.
        .accessibilityElement(children: .contain)
    }

    /// `.card-top{display:flex;align-items:baseline;justify-content:space-between}`
    private var top: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let caption {
                Text(caption).hwEyebrow()
            }
            Spacer(minLength: 0)
            if let subtitle {
                subtitle
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
            }
        }
        // Each end wraps onto more lines rather than truncating. The row itself stays a row — the caption
        // and the subtitle keep their ends of it even at AX5.
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("Card — every combination of its slots") {
    ScrollView {
        VStack(spacing: 14) {
            HWCard(caption: "This month", subtitle: Text(verbatim: "12 expenses")) {
                Text(verbatim: "₹42,180").font(.hw(.display))
            }
            HWCard(caption: "This month") {
                Text(verbatim: "₹42,180").font(.hw(.display))
            }
            HWCard(subtitle: Text(verbatim: "updated just now")) {
                Text(verbatim: "₹42,180").font(.hw(.heading))
            }
            HWCard {
                Text(verbatim: "No caption, no subtitle — just content.").font(.hw(.body))
            }
        }
        .padding()
    }
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the caption and subtitle wrap rather than truncating") {
    HWCard(caption: "This month", subtitle: Text(verbatim: "12 expenses")) {
        Text(verbatim: "₹42,180").font(.hw(.display))
    }
    .padding()
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

// Latin digits under `ar`, which is ADR-0011's decision rather than an oversight: UAE financial figures
// are conventionally written in Western digits and the server formats them that way.
#Preview("RTL") {
    HWCard(caption: "هذا الشهر", subtitle: Text(verbatim: "12 مصروفاً")) {
        Text(verbatim: "₹42,180").font(.hw(.display))
    }
    .padding()
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
