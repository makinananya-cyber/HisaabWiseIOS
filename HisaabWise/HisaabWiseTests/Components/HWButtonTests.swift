import SwiftUI
import Testing

@testable import HisaabWise

/// The button's variants and its two non-ready treatments, as assertions.
///
/// The appearance is pulled out of `body` as a value for the same reason ``StatePresentation`` is: "the
/// four variants are visually distinct" and "there is exactly one disabled treatment" are rules a test
/// can check, and pixels a reviewer cannot.
@Suite("HWButton")
@MainActor
struct HWButtonTests {
    // MARK: The variants

    @Test("the design's variants are all present, and only those")
    func everyVariant() {
        // `.btn` in the design carries primary · soft · ghost · quiet, Expenses' `.addline` is the dashed
        // fifth (#18), and Account's `.logout` is the destructive sixth (#23). One invented here would be a
        // variant with no design behind it; a missing one is a screen about to inline it.
        #expect(HWButtonVariant.allCases.count == 6)
        #expect(HWButtonVariant.allCases == [.primary, .soft, .ghost, .quiet, .dashed, .destructive])
    }

    /// **Exactly one variant is dashed**, which is the whole of what distinguishes `.addline` from `.btn-quiet`
    /// besides its ink — and a dash is invisible to `Equatable` unless the appearance carries it, which is why
    /// `borderDash` is a field rather than something the view decides.
    @Test("only the dashed variant has a dash, on both surfaces")
    func onlyDashedIsDashed() {
        for appearance in HWAppearance.allCases {
            for variant in HWButtonVariant.allCases {
                let dashed = HWButtonAppearance(
                    variant: variant,
                    appearance: appearance,
                    palette: .standard
                ).borderDash != nil
                #expect(dashed == (variant == .dashed), "\(appearance)/\(variant) dash")
            }
        }
    }

    @Test("no two variants resolve to the same appearance on surface")
    func variantsAreDistinct() {
        let appearances = HWButtonVariant.allCases.map {
            HWButtonAppearance(variant: $0, palette: .standard)
        }

        // Pairwise rather than `Set`: the failure message should name the pair.
        for (index, appearance) in appearances.enumerated() {
            for other in appearances[(index + 1)...] {
                #expect(appearance != other, "two variants draw identically")
            }
        }
    }

    /// **On `brand` the rule has one exception, and it is the design's.** There is no `.btn-soft` on the galaxy
    /// surface — its secondary filled control *is* `.btn-ghost` — so those two resolve alike there and the
    /// other pairs still do not. Stated rather than left to the suite above, which would otherwise read as
    /// asserting something false of half the vocabulary (ADR-0029).
    @Test("on brand, soft is the ghost and every other pair is still distinct")
    func brandCollapsesSoftIntoGhost() {
        func appearance(_ variant: HWButtonVariant) -> HWButtonAppearance {
            HWButtonAppearance(variant: variant, appearance: .brand, palette: .standard)
        }

        #expect(appearance(.soft) == appearance(.ghost))
        #expect(appearance(.primary) != appearance(.ghost))
        #expect(appearance(.primary) != appearance(.quiet))
        #expect(appearance(.ghost) != appearance(.quiet))
        // The destructive form shares the ghost's fill on brand and nothing else: the ink and the hairline are
        // both the brand's *own* danger value, which is a different colour from the surface's (ADR-0021).
        #expect(appearance(.destructive) != appearance(.ghost))
        #expect(appearance(.destructive) != appearance(.quiet))
        #expect(appearance(.destructive) != appearance(.primary))
    }

    /// The two appearances are the design's two surfaces, and **no variant looks the same on both** — which is
    /// the whole reason the parameter exists rather than a mode (ADR-0021).
    @Test("every variant is drawn differently on the two surfaces", arguments: HWButtonVariant.allCases)
    func theTwoSurfacesNeverAgree(_ variant: HWButtonVariant) {
        let surface = HWButtonAppearance(variant: variant, appearance: .surface, palette: .standard)
        let brand = HWButtonAppearance(variant: variant, appearance: .brand, palette: .standard)

        #expect(surface != brand, "\(variant) draws identically on both surfaces")
        // And the shapes differ: brand buttons are pills, in-app ones use the card radius.
        #expect(brand.radius == .pill)
        #expect(surface.radius == .large)
    }

    @Test("the appearances are the design's two surfaces, and only those")
    func thereAreTwoAppearances() {
        #expect(HWAppearance.allCases == [.surface, .brand])
    }

    @Test("only primary is a gradient, and only primary, soft and destructive are raised")
    func fillAndElevationFollowTheDesign() {
        func appearance(_ variant: HWButtonVariant) -> HWButtonAppearance {
            HWButtonAppearance(variant: variant, palette: .standard)
        }

        // `.btn-primary{background:linear-gradient(112deg,--galaxy,--planetary)}` is the only gradient
        // among the four; the rest are flat or transparent.
        if case .gradient = appearance(.primary).fill {} else {
            Issue.record("primary is not a gradient")
        }
        for variant in [HWButtonVariant.soft, .ghost, .quiet, .dashed, .destructive] {
            if case .gradient = appearance(variant).fill {
                Issue.record("\(variant) is a gradient — only primary is")
            }
        }

        // `--shadow-m` on primary, `--shadow-s` on soft and on `.logout`, none on ghost or quiet.
        #expect(appearance(.primary).elevation != nil)
        #expect(appearance(.soft).elevation != nil)
        #expect(appearance(.destructive).elevation != nil)
        #expect(appearance(.ghost).elevation == nil)
        #expect(appearance(.quiet).elevation == nil)
        #expect(appearance(.dashed).elevation == nil)

        // **On `brand` nothing is raised**, including primary: the design puts a blurred glow *behind* the
        // landing CTA rather than a shadow under it, and the glow is the screen's to draw because it sits
        // outside the control's bounds (ADR-0029).
        for variant in HWButtonVariant.allCases {
            #expect(
                HWButtonAppearance(variant: variant, appearance: .brand, palette: .standard).elevation == nil,
                "\(variant) is raised on brand, where the design draws no shadow"
            )
        }
    }

    /// **Two variants have no fill and they are the two the design draws unfilled** — `.btn-quiet` and
    /// `.addline`. They are still distinct, because one is bordered with a hairline and the other with a dash in
    /// a different ink; `variantsAreDistinct` above is what states that.
    @Test("only the quiet and dashed variants have no fill")
    func theUnfilledVariants() {
        for variant in HWButtonVariant.allCases {
            let unfilled = HWButtonAppearance(variant: variant, palette: .standard).fill == .unfilled
            #expect(unfilled == (variant == .quiet || variant == .dashed), "\(variant) fill")
        }
    }

    // MARK: The two treatments no screen invents

    @Test("disabled and in-flight are neither ready nor each other")
    func statesAreDistinct() {
        #expect(HWButtonState.allCases.count == 3)
        #expect(!HWButtonState.disabled.isReady)
        #expect(!HWButtonState.inFlight.isReady)
        #expect(HWButtonState.ready.isReady)
    }

    @Test("only disabled dims, and only in-flight shows progress")
    func treatmentsDoNotOverlap() {
        // `.btn[disabled]{opacity:.45}` and `.btn.loading{.lbl opacity:0; .spin opacity:1}` are two
        // different things in the design, and a screen that conflated them would show a dimmed spinner.
        #expect(HWButtonState.disabled.opacity < 1)
        #expect(HWButtonState.ready.opacity == 1)
        #expect(HWButtonState.inFlight.opacity == 1)

        #expect(HWButtonState.inFlight.showsProgress)
        #expect(!HWButtonState.ready.showsProgress)
        #expect(!HWButtonState.disabled.showsProgress)
    }

    /// The CSS drops the shadow on `.btn[disabled]` and on nothing else — `.btn.loading` only sets
    /// `pointer-events:none`. A flattened in-flight button would read as unavailable while it works.
    @Test("only disabled is flattened; a busy button keeps its elevation")
    func onlyDisabledLosesItsElevation() {
        #expect(HWButtonState.ready.keepsElevation)
        #expect(HWButtonState.inFlight.keepsElevation)
        #expect(!HWButtonState.disabled.keepsElevation)
    }

    /// The spinner is the only thing on screen while a button works, and a `ProgressView` reaches VoiceOver
    /// silently. Without a value the control goes quiet exactly when it has something to say.
    @Test("only the in-flight state has an accessibility value")
    func onlyInFlightSpeaks() {
        #expect(HWButtonState.inFlight.accessibilityValue == Text(HWComponentCopy.inFlight))
        for state in [HWButtonState.ready, .disabled] {
            #expect(state.accessibilityValue == Text(verbatim: ""), "\(state) speaks when it should not")
        }
    }

    // MARK: It renders

    @Test("every variant renders in every state, through the real environment")
    func rendersEveryVariantInEveryState() {
        for variant in HWButtonVariant.allCases {
            for state in HWButtonState.allCases {
                let button = HWButton("component.button.inFlight", variant: variant, state: state) {}
                #expect(TestBench.render(button) != nil, "\(variant)/\(state) did not render")
            }
        }
    }

    /// The icon and edit forms carry the same three states as the full-width one, so a screen saving from
    /// an edit toggle has no reason to invent an in-flight treatment of its own.
    @Test("the icon and edit forms render in every state")
    func iconAndEditFormsRender() {
        for state in HWButtonState.allCases {
            let icon = HWIconButton("component.sheet.close", systemImage: "xmark", state: state) {}
            #expect(TestBench.render(icon) != nil, "icon button \(state) did not render")

            for isOn in [false, true] {
                let edit = HWEditButton(
                    "component.button.inFlight",
                    systemImage: "pencil",
                    isOn: isOn,
                    state: state
                ) {}
                #expect(TestBench.render(edit) != nil, "edit button isOn=\(isOn) \(state) did not render")
            }
        }
    }

    // MARK: Copy

    @Test("the component's own copy is in the String Catalogue")
    func copyExists() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: HWComponentCopy.keys)
    }
}
