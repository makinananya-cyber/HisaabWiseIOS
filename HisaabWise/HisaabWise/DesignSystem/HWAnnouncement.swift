import Foundation
import SwiftUI

/// The one way the app says something VoiceOver would otherwise never hear.
///
/// ADR-0012 names two cases — the Learn combo and lesson completion — where **neither form of the feedback
/// reaches VoiceOver on its own**: the animated form is a movement, and the reduced form is a static badge
/// that appears without moving focus. A third case arrived with the state taxonomy: a placeholder replaced
/// by a *different* placeholder is the same layout with different words in it, and nothing about that is an
/// event as far as VoiceOver is concerned (see ``StateView``).
///
/// **Why this exists rather than a call to `AccessibilityNotification` at each site.** An announcement is
/// the only copy in the app that is not drawn by a `Text`, so it is the only copy that does not get the
/// environment's locale for free. `String(localized:)` resolves against the *resource's* locale, and every
/// string in this app is a literal created in a type initialiser long before a screen exists — so the
/// locale it captured is the device's, not the one the user chose in the app (ADR-0011, ADR-0024). Left
/// alone, an Arabic reader gets English speech, and with English-only copy until Phase 5 nobody would
/// notice. `AccessibilityTests` asserts that nothing else posts an announcement.
///
/// The locale is passed in rather than read here: this is not a view, and the value belongs to whichever
/// view is doing the announcing — `@Environment(\.locale)`, which `hwLanguage(_:)` set at the root.
enum HWAnnouncement {
    /// Whether the announcement waits its turn.
    enum Priority: Sendable {
        /// Queues behind whatever VoiceOver is saying. Right for anything the user can also read on screen.
        case standard

        /// Interrupts. Right for feedback that is *about* what the user just did — a combo lands while
        /// VoiceOver is still reading the question that produced it, and an announcement that arrives after
        /// they have moved on is worse than silence.
        case immediate
    }

    /// Resolves `message` against `locale`, which is the whole job.
    ///
    /// Exposed separately from ``post(_:in:priority:)`` because posting cannot be observed: a test can
    /// assert what would be spoken, and nothing can assert that VoiceOver spoke it.
    static func text(_ message: LocalizedStringResource, in locale: Locale) -> String {
        var resource = message
        resource.locale = locale
        return String(localized: resource)
    }

    /// The announcement as the platform wants it: the resolved string, carrying its priority as an
    /// attribute.
    static func announcement(
        _ message: LocalizedStringResource,
        in locale: Locale,
        priority: Priority = .standard
    ) -> AttributedString {
        var announcement = AttributedString(text(message, in: locale))
        announcement.accessibilitySpeechAnnouncementPriority = switch priority {
        case .standard: .default
        case .immediate: .high
        }
        return announcement
    }

    /// Says it. A no-op when no assistive technology is running, which is what makes it safe to call from a
    /// screen unconditionally rather than behind a check of its own.
    static func post(
        _ message: LocalizedStringResource,
        in locale: Locale,
        priority: Priority = .standard
    ) {
        AccessibilityNotification.Announcement(announcement(message, in: locale, priority: priority)).post()
    }
}
