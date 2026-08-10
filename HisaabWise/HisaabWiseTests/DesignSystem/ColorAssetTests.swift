import SwiftUI
import Testing
import UIKit

@testable import HisaabWise

extension Bundle {
    /// The app bundle, located through a type the design system owns rather than through `Fixtures`,
    /// so this suite does not hang off the `#if DEBUG` layer.
    static let designSystem = Bundle(for: ThemeManager.self)
}

/// The catalogue is checked against the design's own numbers.
///
/// Issue #6 says "the design's own values are the source of truth; do not re-pick them by eye", and the
/// only way to keep that true a month from now is to assert it. Every expectation below is transcribed
/// from the `:root` blocks of `HisaabwiseDesigns/HisaabWise 6.html`, with the CSS custom property named
/// beside it. Re-extract them with:
///
/// ```
/// grep -A40 ':root{' "HisaabwiseDesigns/HisaabWise 6.html"
/// ```
@Suite("Colour assets")
struct ColorAssetTests {
    /// semantic asset name → (hex, alpha, the design's property)
    static let expected: [(name: String, hex: String, alpha: CGFloat, source: String)] = [
        // in-app surfaces — home · expenses · learn · reports · account
        ("hwBackground", "FFF9F0", 1.0, "--bg / --milky"),
        ("hwBackgroundSecondary", "F7F2EB", 1.0, "--bg-2 / --meteor"),
        ("hwSurface", "FFFFFF", 1.0, "--card"),
        ("hwInk", "081F5C", 1.0, "--ink / --galaxy"),
        ("hwInkSecondary", "081F5C", 0.66, "--ink-2"),
        ("hwInkTertiary", "081F5C", 0.44, "--ink-3"),
        ("hwSeparator", "334EAC", 0.13, "--line"),
        ("hwSeparatorStrong", "334EAC", 0.24, "--line-2"),
        ("hwAccent", "334EAC", 1.0, "--planetary"),
        ("hwAccentSoft", "D0E3FF", 1.0, "--sky"),
        ("hwAccentDeep", "081F5C", 1.0, "--galaxy"),
        ("hwTint", "D0E3FF", 1.0, "--tint"),
        ("hwTintSecondary", "BAD6EB", 1.0, "--tint-2 / --venus"),
        ("hwAccentMuted", "7096D1", 1.0, "--universe"),
        ("hwDanger", "C0453A", 1.0, "--danger (in-app)"),
        ("hwDangerSoft", "C0453A", 0.09, "--danger-soft"),
        ("hwEmptyTrack", "E5E2DA", 1.0, "--empty"),
        ("hwLocked", "C9CFDF", 1.0, "--lock"),
        ("hwLockedSoft", "E4E8F2", 1.0, "--lock-2"),
        // brand surfaces — landing · auth
        ("hwBrandBackground", "081F5C", 1.0, "--galaxy"),
        ("hwBrandBackgroundDeep", "05143C", 1.0, "--galaxy-deep"),
        ("hwBrandBackgroundLift", "0E2E73", 1.0, "--galaxy-lift"),
        ("hwBrandInk", "FFF9F0", 1.0, "--text / --milky"),
        ("hwBrandInkSecondary", "BAD6EB", 1.0, "--muted / --venus"),
        ("hwBrandInkAccent", "D0E3FF", 1.0, "--accent / --sky"),
        ("hwBrandSurface", "D0E3FF", 0.07, "--card (landing/auth)"),
        ("hwBrandSeparator", "D0E3FF", 0.16, "--border"),
        ("hwBrandSeparatorStrong", "D0E3FF", 0.42, "--border-lit"),
        ("hwBrandDanger", "FFC9C0", 1.0, "--danger (auth)"),
        // six category slots
        ("hwCategoryRent", "3D5AF1", 1.0, "--s1 indigo"),
        ("hwCategoryGroceries", "F4531F", 1.0, "--s2 coral"),
        ("hwCategoryTransport", "009B84", 1.0, "--s3 teal"),
        ("hwCategoryUtilities", "CE8500", 1.0, "--s4 marigold"),
        ("hwCategoryEntertainment", "7C4DEF", 1.0, "--s5 violet"),
        ("hwCategoryOther", "E0357F", 1.0, "--s6 rose"),
        // five Learn unit accents
        ("hwUnitSun", "F0B429", 1.0, "--sun"),
        ("hwUnitSunSoft", "FFF1D4", 1.0, "--sun-soft"),
        ("hwUnitSunDeep", "C98A10", 1.0, "--sun-deep"),
        ("hwUnitMint", "2FA37C", 1.0, "--mint"),
        ("hwUnitMintSoft", "DAF2E9", 1.0, "--mint-soft"),
        ("hwUnitMintDeep", "1E7B5C", 1.0, "--mint-deep"),
        ("hwUnitCoral", "E8705C", 1.0, "--coral"),
        ("hwUnitCoralSoft", "FDE3DD", 1.0, "--coral-soft"),
        ("hwUnitCoralDeep", "C24E3B", 1.0, "--coral-deep"),
        ("hwUnitViolet", "7B6BD6", 1.0, "--violet"),
        ("hwUnitVioletSoft", "E9E5FB", 1.0, "--violet-soft"),
        ("hwUnitVioletDeep", "5B4CB0", 1.0, "--violet-deep"),
        // savings-meter ramp
        ("hwMeterNothing", "F2554E", 1.0, "--r1"),
        ("hwMeterLow", "FA8A47", 1.0, "--r2"),
        ("hwMeterHalf", "F9C548", 1.0, "--r3"),
        ("hwMeterHigh", "A2CB42", 1.0, "--r4"),
        ("hwMeterReached", "1FC186", 1.0, "--r5"),
    ]

    @Test("every semantic colour resolves from the catalogue")
    func everyColourResolves() throws {
        // A missing asset is a test failure, not a pink rectangle at runtime.
        for token in Self.expected {
            #expect(
                UIColor(named: token.name, in: .designSystem, compatibleWith: nil) != nil,
                "no colour set named \(token.name)"
            )
        }
    }

    @Test("every colour carries the design's exact value")
    func everyColourMatchesTheDesign() throws {
        for token in Self.expected {
            let resolved = try #require(
                UIColor(named: token.name, in: .designSystem, compatibleWith: nil),
                "no colour set named \(token.name)"
            )
            let (r, g, b, a) = try components(of: resolved)
            let (er, eg, eb) = Self.channels(token.hex)

            // 1/255 tolerance: the catalogue stores 8-bit channels, floats come back divided.
            let tolerance = 1.0 / 255.0
            #expect(abs(r - er) < tolerance, "\(token.name) red — expected \(token.source)")
            #expect(abs(g - eg) < tolerance, "\(token.name) green — expected \(token.source)")
            #expect(abs(b - eb) < tolerance, "\(token.name) blue — expected \(token.source)")
            #expect(abs(a - token.alpha) < 0.005, "\(token.name) alpha — expected \(token.source)")
        }
    }

    /// ADR-0001 ships one appearance. A dark variant in the catalogue would be dark mode arriving by
    /// accident, one colour set at a time.
    @Test("no colour set declares a dark appearance")
    func catalogueIsSingleAppearance() throws {
        let catalogue = SourceTree.appSources
            .appending(path: "Resources")
            .appending(path: "Assets.xcassets")

        var checked = 0
        let walker = try #require(FileManager.default.enumerator(at: catalogue, includingPropertiesForKeys: nil))
        for case let url as URL in walker where url.pathExtension == "colorset" {
            let json = try String(contentsOf: url.appending(path: "Contents.json"), encoding: .utf8)
            #expect(
                !json.contains("appearances"),
                "\(url.lastPathComponent) declares an appearance variant — light-only (ADR-0001)"
            )
            checked += 1
        }
        // Guards against the walk finding nothing and the assertions above passing vacuously.
        #expect(checked >= Self.expected.count)
    }

    /// The design states this constraint in a comment beside the slots: "every slot clears 3:1 against
    /// the white card". A donut is unreadable otherwise, and a comment is not enforcement.
    @Test("every category colour clears 3:1 against the card")
    func categoryColoursClearContrastOnCard() throws {
        let card = try #require(UIColor(named: "hwSurface", in: .designSystem, compatibleWith: nil))
        let categories = Self.expected.filter { $0.name.hasPrefix("hwCategory") }

        #expect(categories.count == 6, "the design defines six category slots")
        for category in categories {
            let colour = try #require(UIColor(named: category.name, in: .designSystem, compatibleWith: nil))
            let ratio = try contrastRatio(colour, card)
            #expect(ratio >= 3.0, "\(category.name) is \(String(format: "%.2f", ratio)):1 on the card")
        }
    }

    @Test("the four unit-accent triads are complete, and the fifth reuses the accent")
    func unitAccentsAreComplete() {
        // The fifth accent reuses the accent triad rather than carrying byte-identical copies of it —
        // the design spells it `--acc: planetary` for the same reason (ADR-0021).
        for name in ["hwAccent", "hwAccentSoft", "hwAccentDeep"] {
            #expect(UIColor(named: name, in: .designSystem, compatibleWith: nil) != nil, "missing \(name)")
        }
        for unit in ["Sun", "Mint", "Coral", "Violet"] {
            for suffix in ["", "Soft", "Deep"] {
                let name = "hwUnit\(unit)\(suffix)"
                #expect(
                    UIColor(named: name, in: .designSystem, compatibleWith: nil) != nil,
                    "missing \(name)"
                )
            }
        }
    }

    // MARK: - Helpers

    private func components(of colour: UIColor) throws -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(colour.getRed(&r, green: &g, blue: &b, alpha: &a))
        return (r, g, b, a)
    }

    private static func channels(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
        func channel(_ range: Range<String.Index>) -> CGFloat {
            CGFloat(UInt8(hex[range], radix: 16) ?? 0) / 255.0
        }
        let i = hex.startIndex
        return (
            channel(i..<hex.index(i, offsetBy: 2)),
            channel(hex.index(i, offsetBy: 2)..<hex.index(i, offsetBy: 4)),
            channel(hex.index(i, offsetBy: 4)..<hex.index(i, offsetBy: 6))
        )
    }

    /// WCAG 2.1 relative-luminance contrast ratio.
    private func contrastRatio(_ a: UIColor, _ b: UIColor) throws -> Double {
        func luminance(_ colour: UIColor) throws -> Double {
            let (r, g, b, _) = try components(of: colour)
            func linear(_ c: CGFloat) -> Double {
                let c = Double(c)
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let (l1, l2) = (try luminance(a), try luminance(b))
        let (lighter, darker) = l1 > l2 ? (l1, l2) : (l2, l1)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
