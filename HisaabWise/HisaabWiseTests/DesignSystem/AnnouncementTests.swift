import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// ``HWAnnouncement`` — the one way the app says something VoiceOver would otherwise never hear
/// (ADR-0012).
///
/// The interesting claim is not that it posts. It is **which language it posts in**: an announcement is
/// the one piece of copy in the app that is not drawn by a `Text`, so it does not get the environment
/// locale for free the way every other string does (ADR-0011, ADR-0024). Resolving it against the
/// device's locale instead would give an Arabic reader English speech, and with English-only copy that
/// failure is invisible until Phase 5.
@Suite("Announcements")
@MainActor
struct AnnouncementTests {
    /// Two locales the app does not ship, deliberately: this asserts that the locale *reaches* the
    /// resolution, and the two shipped languages have identical copy today so they could not tell these
    /// apart. The grouping separator is the part of resolution whose result is visible — `en_US` gives
    /// 1,234 and `de_DE` gives 1.234.
    @Test("the announcement resolves against the locale it is given, not the device's")
    func theLocaleReachesTheResolution() {
        let message = LocalizedStringResource("\(1234)")

        let english = HWAnnouncement.text(message, in: Locale(identifier: "en_US"))
        let german = HWAnnouncement.text(message, in: Locale(identifier: "de_DE"))

        #expect(english != german)
        #expect(english == "1,234")
        #expect(german == "1.234")
    }

    /// The half that would otherwise be assumed: a resource created as a literal long before any screen
    /// existed — which is every string in `StateCopy` and `ErrorCopy` — has captured *some* locale, and the
    /// helper has to override it rather than inherit it.
    @Test("a resource's own captured locale does not win")
    func theCapturedLocaleIsOverridden() {
        var captured = LocalizedStringResource("\(1234)")
        captured.locale = Locale(identifier: "de_DE")

        #expect(HWAnnouncement.text(captured, in: Locale(identifier: "en_US")) == "1,234")
    }

    @Test("catalogue copy comes back as its English value")
    func catalogueCopyResolves() throws {
        let english = try #require(CatalogueCopy.english(in: try CatalogueCopy.entry("state.offline")))

        #expect(HWAnnouncement.text("state.offline", in: Locale(identifier: "en")) == english)
    }

    // MARK: - Priority

    /// An announcement about a combo lands while the user is still reading the question that produced it,
    /// so it has to be able to interrupt. Asserted by reading the attribute back, which also pins that the
    /// platform attribute is the one being set.
    @Test("an interrupting announcement carries the high priority attribute")
    func immediatePriorityIsCarried() {
        let announcement = HWAnnouncement.announcement(
            "state.offline",
            in: Locale(identifier: "en"),
            priority: .immediate
        )

        #expect(announcement.accessibilitySpeechAnnouncementPriority == .high)
    }

    @Test("an ordinary announcement waits its turn")
    func standardPriorityIsCarried() {
        let announcement = HWAnnouncement.announcement("state.offline", in: Locale(identifier: "en"))

        #expect(announcement.accessibilitySpeechAnnouncementPriority == .default)
    }

    @Test("the spoken text is the resolved copy, whatever the priority")
    func theTextSurvivesTheAttribute() {
        for priority in [HWAnnouncement.Priority.standard, .immediate] {
            let announcement = HWAnnouncement.announcement(
                "\(1234)",
                in: Locale(identifier: "en_US"),
                priority: priority
            )

            #expect(String(announcement.characters) == "1,234")
        }
    }

    /// Posting with no assistive technology running is a no-op rather than an error, which is what makes it
    /// safe to call unconditionally from a screen. Nothing to assert but that it survives the call.
    @Test("posting is safe with VoiceOver off")
    func postingIsSafe() {
        HWAnnouncement.post("state.offline", in: Locale(identifier: "en"))
        HWAnnouncement.post("state.offline", in: Locale(identifier: "en"), priority: .immediate)
    }
}
