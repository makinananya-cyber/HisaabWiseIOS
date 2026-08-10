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

    @Test("the design's four variants are all present")
    func fourVariants() {
        // `.btn` in the design carries exactly these: primary · soft · ghost · quiet. A fifth invented
        // here would be a variant with no design behind it; a missing one is a screen about to inline it.
        #expect(HWButtonVariant.allCases.count == 4)
        #expect(HWButtonVariant.allCases == [.primary, .soft, .ghost, .quiet])
    }

    @Test("no two variants resolve to the same appearance")
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

    @Test("only primary is a gradient, and only primary and soft are raised")
    func fillAndElevationFollowTheDesign() {
        func appearance(_ variant: HWButtonVariant) -> HWButtonAppearance {
            HWButtonAppearance(variant: variant, palette: .standard)
        }

        // `.btn-primary{background:linear-gradient(112deg,--galaxy,--planetary)}` is the only gradient
        // among the four; the rest are flat or transparent.
        if case .gradient = appearance(.primary).fill {} else {
            Issue.record("primary is not a gradient")
        }
        for variant in [HWButtonVariant.soft, .ghost, .quiet] {
            if case .gradient = appearance(variant).fill {
                Issue.record("\(variant) is a gradient — only primary is")
            }
        }

        // `--shadow-m` on primary, `--shadow-s` on soft, none on ghost or quiet.
        #expect(appearance(.primary).elevation != nil)
        #expect(appearance(.soft).elevation != nil)
        #expect(appearance(.ghost).elevation == nil)
        #expect(appearance(.quiet).elevation == nil)
    }

    @Test("the quiet variant has no fill, and every other one does")
    func quietIsTheOnlyUnfilledVariant() {
        for variant in HWButtonVariant.allCases {
            let unfilled = HWButtonAppearance(variant: variant, palette: .standard).fill == .unfilled
            #expect(unfilled == (variant == .quiet), "\(variant) fill")
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
