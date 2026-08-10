import Foundation

/// The copy the components own, rather than take from a caller.
///
/// It is a very short list on purpose. A component takes its words from the screen — a button's title,
/// a field's label — because only the screen knows what it is asking for. What is left here is the copy
/// that belongs to the *control* and would otherwise be written twelve times: the close affordance every
/// sheet has, and the state a spinner cannot announce.
///
/// Gathered into one type so that ``keys`` can be asserted against the String Catalogue in one place;
/// a key with nothing behind it shows the user the key (ADR-0011).
enum HWComponentCopy {
    /// The `.sheet-x` affordance. Icon-only, so this is the whole of what VoiceOver reads.
    static let closeSheet: LocalizedStringResource = "component.sheet.close"

    /// Read as the button's value while a request is in flight. The spinner that replaces the label is
    /// invisible to VoiceOver, so without this the control goes silent exactly when it is busy
    /// (ADR-0012).
    static let inFlight: LocalizedStringResource = "component.button.inFlight"

    /// Every key the components render themselves.
    static let keys = [closeSheet.key, inFlight.key]
}
