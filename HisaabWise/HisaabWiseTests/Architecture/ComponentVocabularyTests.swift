import Foundation
import Testing

/// The scans that keep `Components/` drawing with the design system rather than beside it.
///
/// `LayeringTests` already asserts the two rules that apply to the whole app — no colour reaches a use
/// site except by semantic name, and no raw palette name appears anywhere. What is left is specific to a
/// component, and is the criterion issue #26 asks to be asserted rather than reviewed: a component gets
/// **every** colour, size, and elevation from a token, so the later dark-mode palette swap stays a swap.
///
/// Same standing as the other structural suites: strictly weaker than a compiler, and the only
/// enforcement there is.
@Suite("Component vocabulary")
struct ComponentVocabularyTests {
    /// A scan that read no files would pass silently, so the layer is checked to have grown components
    /// at all before anything is asserted about them.
    @Test("the components layer is populated")
    func componentsExist() throws {
        let files = try SourceTree.swiftFiles(in: "Components")

        // `Components.swift` is the namespace; the rest are the vocabulary.
        #expect(files.count > 1, "Components/ holds only its namespace — the scans below assert nothing")
    }

    /// A component that reaches for `Color.hwInk` has gone around `ThemeManager`, and a palette swap
    /// cannot reach it — the asset symbol resolves to one colour set forever. The palette is the seam;
    /// the asset catalogue is behind it.
    @Test("no component reaches an asset symbol directly — colour comes from the palette")
    func componentsAskThePalette() throws {
        try SourceTree.expectAbsent(
            // `Color(` in any form: the asset symbols (`Color.hw…`), a bridged `UIColor`, a colour built
            // from channels, and `Color(.systemBackground)` — which `LayeringTests`' own list does not
            // reach, since it names `Color(.sRGB` specifically.
            ["Color.hw", "UIColor", "Color(red:", "Color(hue:", "Color(white:", "Color(."],
            from: ["Components"],
            because: "a component asks theme.palette for a role; the asset symbols are behind it (ADR-0001)"
        )
    }

    /// The type scale is eight steps anchored to `Font.TextStyle` so text scales to AX5 unclamped
    /// (ADR-0012). A `.system(size:)` pins it, and a bare `.font(.body)` sidesteps the scale entirely —
    /// which is how a screen ends up 0.5pt away from its neighbour.
    @Test("no component sets a font except through the type scale")
    func componentsUseTheTypeScale() throws {
        try SourceTree.expectAbsent(
            [
                ".system(size:", "Font.system", ".custom(",
                // The system text styles, named directly rather than through `HWTextStyle`.
                ".font(.largeTitle", ".font(.title", ".font(.headline", ".font(.subheadline",
                ".font(.body", ".font(.callout", ".font(.footnote", ".font(.caption",
            ],
            from: ["Components"],
            because: "sizes are owned by HWTextStyle, which is what makes them scale (ADR-0012, issue #6)"
        )
    }

    /// Dynamic Type is unclamped on all text; only the data visualisations clamp, and none of those is a
    /// component (ADR-0012). A clamp here would cap every screen that used the control.
    ///
    /// The scan is for the *range* form — `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)` — because that is
    /// what a clamp is. A preview pinning one size is not clamping anything; it is showing AX3.
    @Test("no component clamps Dynamic Type")
    func componentsDoNotClampDynamicType() throws {
        try SourceTree.expectAbsent(
            ["dynamicTypeSize(..."],
            from: ["Components"],
            because: "text scales unclamped; only the visualisations clamp, and none is a component (ADR-0012)"
        )
    }

    /// `.leading` and `.trailing` mirror in Arabic; `.left` and `.right` do not. ADR-0011 puts string
    /// externalisation in Phase 1 for the same reason — RTL is not a Phase 5 sweep.
    @Test("no component pins an edge to the left or the right")
    func componentsAreDirectionAgnostic() throws {
        try SourceTree.expectAbsent(
            ["alignment: .left", "alignment: .right", ".topLeft", ".topRight",
             ".bottomLeft", ".bottomRight", "edge: .left", "edge: .right"],
            from: ["Components"],
            because: "layout mirrors in Arabic, which leading/trailing does and left/right does not (ADR-0011)"
        )
    }

    /// ADR-0011 chooses **Latin digits everywhere, including under `ar`**, and records Eastern Arabic-Indic
    /// digits as deliberately not offered. The RTL previews are the reference a screen author copies, so a
    /// preview showing `٠١٢٣` teaches a digit shape the app will never render.
    @Test("no component writes Eastern Arabic-Indic digits, in a preview or anywhere else")
    func latinDigitsOnly() throws {
        let easternArabicIndic = (0x0660...0x0669).map { String(UnicodeScalar($0)!) }

        try SourceTree.expectAbsent(
            easternArabicIndic,
            from: ["Components"],
            because: "Latin digits everywhere, including under ar — Eastern Arabic-Indic are not offered (ADR-0011)"
        )
    }

    /// Elevation is three tokens folded out of the design's `--shadow-s/m/l`, negative spread included.
    /// A hand-rolled `.shadow(color:…)` in a component is a fourth elevation nobody chose.
    @Test("no component hand-rolls an elevation")
    func componentsUseTheElevationTokens() throws {
        try SourceTree.expectAbsent(
            [".shadow(color:", ".shadow(radius:"],
            from: ["Components"],
            because: "elevation is HWShadow, which already folds the design's negative spread in (issue #6)"
        )
    }

    /// The positive half of the rule. The scans above can only prove that the wrong things are absent; a
    /// component that drew colour from nowhere at all would satisfy every one of them.
    ///
    /// Two exemptions, both principled rather than convenient: a **layout-only** view names no colour, and
    /// a **shape helper** — `hwBox` — is handed colours its caller already resolved. Both are recognised by
    /// what they are, not by name: the scan looks only at files that both declare a drawn type and name a
    /// colour-taking modifier, and it requires `theme.palette` specifically rather than the word `palette`
    /// anywhere in the file, which a preview could satisfy on its own.
    @Test("every component that paints does so through the palette")
    func everyPaintingComponentReadsThePalette() throws {
        let painting = ["foregroundStyle(", ".fill(", ".background(", ".tint(", "fill:"]
        let drawnType = [": View {", ": ViewModifier {"]
        var checked = 0

        for file in try SourceTree.swiftFiles(in: "Components") {
            let code = try SourceTree.codeLines(of: file)
            guard code.contains(where: { line in drawnType.contains(where: line.contains) }),
                  code.contains(where: { line in painting.contains(where: line.contains) })
            else { continue }

            checked += 1
            #expect(
                code.contains { $0.contains("theme.palette") },
                "Components/\(file.lastPathComponent) paints without asking the palette for a role"
            )
        }

        #expect(checked > 0, "no component paints anything — this scan read nothing")
    }

    /// Every interactive component carries a VoiceOver surface, because accessibility arrives with the
    /// component rather than being added per screen (ADR-0012). A `Button` with no `accessibility*`
    /// modifier is a control whose label is whatever its glyph happens to be.
    @Test("every component holding a Button carries a VoiceOver surface")
    func interactiveComponentsAreLabelled() throws {
        var checked = 0

        for file in try SourceTree.swiftFiles(in: "Components") {
            let code = try SourceTree.codeLines(of: file)
            // `HWPressStyle` is a `ButtonStyle`; it decorates a button rather than declaring one.
            guard code.contains(where: { $0.contains("Button(action:") }) else { continue }

            checked += 1
            #expect(
                code.contains { $0.contains(".accessibility") },
                "Components/\(file.lastPathComponent) declares a button with no accessibility surface"
            )
        }

        #expect(checked > 0, "no component declares a button — this scan read nothing")
    }

    /// Reduce Motion *replaces* rather than removes (ADR-0012). A component that animates and never reads
    /// the environment has no replacement to offer — it either keeps the motion or drops it silently.
    @Test("every component that animates reads Reduce Motion")
    func animatingComponentsRespectReduceMotion() throws {
        var checked = 0

        for file in try SourceTree.swiftFiles(in: "Components") {
            let code = try SourceTree.codeLines(of: file)
            guard code.contains(where: { $0.contains(".animation(") || $0.contains(".transition(") })
            else { continue }

            checked += 1
            #expect(
                code.contains { $0.contains("accessibilityReduceMotion") },
                "Components/\(file.lastPathComponent) animates without reading Reduce Motion"
            )
        }

        #expect(checked > 0, "no component animates — this scan read nothing")
    }

    /// Every component has a preview covering its states. ADR-0013 makes previews part of the deliverable
    /// rather than a nicety, and a component with no preview is one nobody will look at until a screen
    /// uses it wrongly.
    @Test("every component has previews, including the RTL and AX3 variants")
    func everyComponentHasPreviews() throws {
        var checked = 0

        for file in try SourceTree.swiftFiles(in: "Components") {
            let source = try String(contentsOf: file, encoding: .utf8)
            // The namespace, the copy table, and the button style are not drawn controls; only a `View`
            // needs a preview.
            guard source.contains(": View {") else { continue }
            // A file that is `#if DEBUG` from its first line is preview scaffolding rather than a
            // component — previewing the preview ground would be circular.
            guard source.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#if DEBUG") == false
            else { continue }

            checked += 1
            let name = file.lastPathComponent

            #expect(source.contains("#Preview"), "\(name) has no preview")
            #expect(source.contains("#if DEBUG"), "\(name)'s previews are not behind #if DEBUG")
            #expect(source.contains("layoutDirection, .rightToLeft"), "\(name) has no RTL preview")
            #expect(source.contains("dynamicTypeSize(.accessibility"), "\(name) has no AX preview")
        }

        #expect(checked > 0, "no component declares a view — this scan read nothing")
    }
}
