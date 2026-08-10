import SwiftUI
import UIKit

@testable import HisaabWise

/// Measurement helpers for the type scale, in the **test** target.
///
/// They live here rather than on ``HWTextStyle`` because nothing in the app should reach for them: the
/// UIKit twin exists only to read a resolved point size, which a SwiftUI `Font` will not report, and the
/// reference sizes are an expectation about Apple's metrics rather than anything the app lays out with.
extension HWTextStyle {
    /// The UIKit twin of ``HWTextStyle/textStyle``.
    var uiTextStyle: UIFont.TextStyle {
        switch textStyle {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }

    /// The point size this step resolves to at the default Dynamic Type setting.
    ///
    /// Asserted so that the documented cluster on each case stays honest, and so the scale can be shown
    /// to be ordered and never below 11pt. Not a layout number.
    var referenceSize: CGFloat {
        switch self {
        case .display: 34
        case .title: 28
        case .heading: 22
        case .subheading: 20
        case .bodyLarge: 16
        case .body: 13
        case .caption: 12
        case .micro: 11
        }
    }

    func pointSize(at category: UIContentSizeCategory) -> CGFloat {
        UIFont.preferredFont(
            forTextStyle: uiTextStyle,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
        ).pointSize
    }
}
