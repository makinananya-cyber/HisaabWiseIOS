import SwiftUI
import Testing

@testable import HisaabWise

/// Every component, at every state it declares, rendered through the real environment.
///
/// The acceptance criterion issue #26 asks for is "renders at every declared state without trapping",
/// and that is exactly as much as this claims. Components read `ThemeManager` from `@Environment`, so
/// poking at `body` would trap on a missing object and prove nothing about the real hierarchy — the same
/// reason `HomeViewTests` renders rather than inspects. Pinned snapshots arrive with the snapshot harness
/// (issue #9); what fails here is a component that cannot be drawn at all.
@Suite("Component rendering")
@MainActor
struct HWComponentRenderTests {
    // MARK: Fields

    @Test("the field renders with and without each of its optional parts")
    func fieldRendersInEveryConfiguration() {
        // The amount field and the email field are this component configured differently, which is the
        // criterion. Both are here, alongside the bare and the invalid forms.
        let configurations: [(String, HWTextField)] = [
            ("bare", HWTextField("Note", text: .constant(""))),
            (
                "email",
                HWTextField(
                    "Email",
                    text: .constant("neeraj@example.ae"),
                    placeholder: "you@example.com",
                    systemImage: "envelope",
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress
                )
            ),
            (
                "amount",
                HWTextField(
                    "Amount",
                    text: .constant("250"),
                    systemImage: "creditcard",
                    keyboardType: .decimalPad
                )
            ),
            (
                "invalid",
                HWTextField(
                    "Email",
                    text: .constant("nope"),
                    systemImage: "envelope",
                    error: "That does not look like an email address."
                )
            ),
        ]

        for (name, field) in configurations {
            #expect(TestBench.render(field) != nil, "the \(name) field did not render")
        }
    }

    // MARK: Text styles

    @Test("the label and eyebrow styles render")
    func textStylesRender() {
        #expect(TestBench.render(Text(verbatim: "Monthly income").hwLabel()) != nil)
        #expect(TestBench.render(Text(verbatim: "Your account").hwEyebrow()) != nil)
    }

    // MARK: Cards

    @Test("the card renders with every combination of its slots")
    func cardRendersWithEverySlotCombination() {
        let captions: [LocalizedStringResource?] = [nil, "This month"]
        let subtitles: [Text?] = [nil, Text(verbatim: "12 expenses")]

        for caption in captions {
            for subtitle in subtitles {
                let card = HWCard(caption: caption, subtitle: subtitle) {
                    Text(verbatim: "₹42,180")
                }
                #expect(
                    TestBench.render(card) != nil,
                    "card caption=\(caption != nil) subtitle=\(subtitle != nil) did not render"
                )
            }
        }
    }

    // MARK: Chips

    @Test("the chip renders selected and unselected, and the code chip renders")
    func chipsRender() {
        for isSelected in [false, true] {
            let chip = HWChip(Text(verbatim: "Feb 2026"), isSelected: isSelected) {}
            #expect(TestBench.render(chip) != nil, "chip isSelected=\(isSelected) did not render")
        }
        #expect(TestBench.render(HWCodeChip("AED")) != nil)
    }

    // MARK: Rows

    @Test("the row renders with every combination of its optional slots")
    func rowRendersWithEverySlotCombination() {
        let subtitles: [Text?] = [nil, Text(verbatim: "Used across the app")]
        let values: [Text?] = [nil, Text(verbatim: "English")]

        for subtitle in subtitles {
            for value in values {
                for showsDisclosure in [false, true] {
                    let row = HWRow(
                        systemImage: "globe",
                        name: Text(verbatim: "Language"),
                        subtitle: subtitle,
                        value: value,
                        showsDisclosure: showsDisclosure
                    ) {}
                    #expect(
                        TestBench.render(row) != nil,
                        "row subtitle=\(subtitle != nil) value=\(value != nil) chevron=\(showsDisclosure)"
                    )
                }
            }
        }
    }

    /// The key row has one shape, not two: the design draws it as `<button class="key-row">` in both
    /// places it appears, because tapping one isolates its wedge in the donut. So what varies is
    /// `isSelected` — `.key-row.on` — and not whether the row is interactive at all.
    @Test("the key row renders isolated and not")
    func keyRowRendersBothSelectionStates() {
        for isSelected in [false, true] {
            let row = HWKeyRow(
                colour: HWPalette.standard.categories.rent,
                name: Text(verbatim: "Rent"),
                share: Text(verbatim: "38%"),
                isSelected: isSelected
            ) {}
            #expect(TestBench.render(row) != nil, "key row isSelected=\(isSelected) did not render")
        }
    }

    // MARK: Sheets

    @Test("the sheet chrome renders with and without a close button, around the shared list")
    func sheetChromeRenders() {
        let withClose = HWSheetChrome(title: "Choose a currency", onClose: {}) {
            HWSheetList {
                HWSheetRow(name: Text(verbatim: "UAE Dirham"), leading: .code("AED"), isSelected: true) {}
            }
        }
        #expect(TestBench.render(withClose) != nil)

        let withoutClose = HWSheetChrome(title: "Category") {
            HWSheetList {
                HWSheetRow(name: Text(verbatim: "Groceries"), leading: .symbol("cart")) {}
            }
        }
        #expect(TestBench.render(withoutClose) != nil)
    }

    @Test("the sheet row renders with a code, with a glyph, and with neither")
    func sheetRowRendersEveryLeadingSlot() {
        // `HWSheetRowLeading` makes "a code *and* a glyph" unrepresentable, so what is enumerated here is
        // every case it has, plus the absent one, times the selection.
        let leadings: [HWSheetRowLeading?] = [nil, .code("AED"), .symbol("cart")]

        for leading in leadings {
            for isSelected in [false, true] {
                let row = HWSheetRow(
                    name: Text(verbatim: "UAE Dirham"),
                    leading: leading,
                    meta: Text(verbatim: "د.إ"),
                    isSelected: isSelected
                ) {}
                #expect(
                    TestBench.render(row) != nil,
                    "sheet row leading=\(String(describing: leading)) selected=\(isSelected)"
                )
            }
        }
    }

    // MARK: Bars

    @Test("the bars render with and without their optional parts")
    func barsRender() {
        #expect(TestBench.render(HWTopBar(title: Text(verbatim: "Expenses"))) != nil)
        #expect(
            TestBench.render(HWTopBar(eyebrow: "This month", title: Text(verbatim: "Expenses"))) != nil
        )

        let withTrailing = HWTopBar(eyebrow: "Your account", title: Text(verbatim: "Settings")) {
            HWEditButton("component.button.inFlight", isOn: false) {}
        }
        #expect(TestBench.render(withTrailing) != nil)

        let bare = HWBackBar(title: Text(verbatim: "Rent"), backLabel: "component.sheet.close") {}
        #expect(TestBench.render(bare) != nil)

        let backWithTrailing = HWBackBar(
            title: Text(verbatim: "Rent"),
            backLabel: "component.sheet.close",
            onBack: {}
        ) {
            HWIconButton("component.sheet.close", systemImage: "trash") {}
        }
        #expect(TestBench.render(backWithTrailing) != nil)
    }

    // MARK: Toasts

    @Test("the toast renders, and its overlay renders in both presentation states")
    func toastRenders() {
        #expect(TestBench.render(HWToast("Expense logged.")) != nil)

        for isPresented in [false, true] {
            let overlaid = Text(verbatim: "a screen").hwToast("Expense logged.", isPresented: isPresented)
            #expect(TestBench.render(overlaid) != nil, "toast isPresented=\(isPresented) did not render")
        }

        // No message and `isPresented` true draws nothing rather than an empty pill — a component that
        // trusted the flag alone would show a blank toast.
        #expect(TestBench.render(Text(verbatim: "a screen").hwToast(nil, isPresented: true)) != nil)
    }

    // MARK: Accessibility settings

    /// Text is unclamped all the way to AX5 (ADR-0012), and a component that only lays out at the default
    /// size is a component that breaks on the first device that does not use it.
    ///
    /// **Reduce Motion is not exercised here**, and cannot be: `accessibilityReduceMotion` is a read-only
    /// environment value bridged from the OS setting, so there is nothing to inject. What can be asserted
    /// is that the replacement exists — see ``HWPressStyleTests`` — and that every animating component
    /// reads the setting, which `ComponentVocabularyTests` scans for.
    @Test("every component renders at AX5")
    func componentsRenderAtAccessibilitySizes() {
        let samples: [(String, AnyView)] = [
            ("button", AnyView(HWButton("component.button.inFlight") {})),
            ("iconButton", AnyView(HWIconButton("component.sheet.close", systemImage: "xmark") {})),
            ("editButton", AnyView(HWEditButton("component.button.inFlight", isOn: true) {})),
            ("field", AnyView(HWTextField("Amount", text: .constant("250"), error: "Too small."))),
            ("card", AnyView(HWCard(caption: "This month") { Text(verbatim: "₹42,180") })),
            ("chip", AnyView(HWChip(Text(verbatim: "Feb 2026"), isSelected: true) {})),
            ("codeChip", AnyView(HWCodeChip("AED"))),
            ("row", AnyView(HWRow(systemImage: "globe", name: Text(verbatim: "Language")) {})),
            (
                "keyRow",
                AnyView(
                    HWKeyRow(
                        colour: HWPalette.standard.categories.rent,
                        name: Text(verbatim: "Rent"),
                        share: Text(verbatim: "38%")
                    ) {}
                )
            ),
            (
                "sheet",
                AnyView(
                    HWSheetChrome(title: "Choose a currency", onClose: {}) {
                        HWSheetList {
                            HWSheetRow(name: Text(verbatim: "UAE Dirham"), leading: .code("AED")) {}
                        }
                    }
                )
            ),
            ("toast", AnyView(HWToast("Expense logged."))),
            ("label", AnyView(Text(verbatim: "Monthly income").hwLabel())),
            ("eyebrow", AnyView(Text(verbatim: "Your account").hwEyebrow())),
            ("topBar", AnyView(HWTopBar(eyebrow: "Your account", title: Text(verbatim: "Settings")))),
            (
                "backBar",
                AnyView(
                    HWBackBar(title: Text(verbatim: "Rent"), backLabel: "component.sheet.close") {}
                )
            ),
        ]

        for (name, view) in samples {
            let ax5 = view.dynamicTypeSize(.accessibility5)
            #expect(TestBench.render(ax5) != nil, "\(name) did not render at AX5")
        }
    }
}

/// The one place Reduce Motion is handled for every tappable component, so the one place it can be
/// asserted as a value.
///
/// `accessibilityReduceMotion` is read-only — there is no way to inject it and re-render — so what is
/// checked is that a *replacement* exists at all. ADR-0012's rule is "replace, never remove", and a
/// `pressedOpacity` of 1 would be removal wearing the rule's name.
@Suite("HWPressStyle")
struct HWPressStyleTests {
    @Test("the Reduce Motion stand-in is a real change, and still legible")
    func reduceMotionReplacementIsNeitherNothingNorInvisible() {
        #expect(HWPressStyle.pressedOpacity < 1, "Reduce Motion removes the feedback rather than replacing it")
        #expect(HWPressStyle.pressedOpacity > 0.5, "the control disappears rather than acknowledging the tap")
    }

    @Test("the design's two press scales are both present and both a shrink")
    func bothPressScalesShrink() {
        // `transform:scale(.97)` on full-width controls, `.94` on the small ones. A scale of 1 is a
        // control with no press feedback at all.
        #expect(HWPressStyle().pressedScale < 1)
        #expect(HWPressStyle.compact.pressedScale < HWPressStyle().pressedScale)
    }
}
