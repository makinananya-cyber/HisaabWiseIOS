import Foundation
@testable import HisaabWise
import Testing

/// The scans over `Configuration/` — the build inputs no Swift file is allowed to know about.
///
/// These read the `.xcconfig` and `Info.plist` files from disk for the same reason `LayeringTests`
/// reads source: nothing here is checked by a compiler. A URL typed into the wrong file, an ATS
/// exception that widened, a fourth configuration whose `.xcconfig` was never written — each of them
/// builds cleanly and is discovered on a device, or worse, in a shipped build (ADR-0010, ADR-0022).
@Suite("Build configuration")
struct BuildConfigurationTests {
    /// The three configurations ADR-0010 names, and the `Info.plist` each one uses. **The one list**:
    /// everything below is derived from it, so a fourth configuration is added here and is then covered
    /// by every assertion rather than by the one whoever adds it remembers.
    private static let configurations = [
        (name: "Debug", plist: "Info-Debug.plist"),
        (name: "Staging", plist: "Info.plist"),
        (name: "Release", plist: "Info.plist"),
    ]

    static let names = configurations.map(\.name)

    /// The configurations that ship. Whatever is not Debug: staging and production are both builds a
    /// user could end up holding.
    static let deployedNames = names.filter { $0 != "Debug" }

    static let plists = Set(configurations.map(\.plist)).sorted()

    // MARK: - The .xcconfig files

    @Test("all three configurations are committed")
    func allThreeExist() throws {
        for name in Self.names {
            let file = SourceTree.configuration.appending(path: "\(name).xcconfig")
            #expect(
                FileManager.default.fileExists(atPath: file.path()),
                "\(name).xcconfig is missing — the configuration it names cannot build"
            )
        }
    }

    @Test("Debug points at the local backend on the loopback interface")
    func debugPointsAtLocalBackend() throws {
        // The exact value, not merely "a localhost URL": the port is what the backend serves on, and a
        // wrong one reads as "the server is down" on every screen rather than "the port is wrong".
        //
        // **8080, not 8787.** The backend moved from Cloudflare Workers to Node (backend ADR-0016), so it
        // is `@hono/node-server` under `npm run dev` rather than `wrangler dev`.
        #expect(try Self.baseURL(in: "Debug") == "http://localhost:8080")
    }

    @Test("staging and production are HTTPS", arguments: Self.deployedNames)
    func deployedConfigurationsAreEncrypted(_ configuration: String) throws {
        #expect(try Self.baseURL(in: configuration).hasPrefix("https://"))
    }

    @Test("every configuration parses, end to end through the real parser", arguments: Self.names)
    func everyConfigurationParses(_ configuration: String) throws {
        // End to end against the real parser, so a value that would trap at launch fails here instead:
        // ``AppConfig`` refuses cleartext for anything but localhost, and refuses a URL with no scheme —
        // which is the shape a forgotten `$()` escape leaves behind, since `//` opens a comment in an
        // .xcconfig and would truncate the value to `http:`.
        let raw = try Self.baseURL(in: configuration)

        // Every key the parse needs, read out of the same `.xcconfig` the build reads — so this is the whole
        // configuration going through `AppConfig`, not the base URL with the rest stubbed. A configuration whose
        // Terms URL would trap at launch fails here.
        let settings = try Self.settings(in: configuration)
        var dictionary: [String: Any] = [:]
        for (key, setting) in Self.plistKeys {
            dictionary[key] = try #require(settings[String(setting.dropFirst(2).dropLast())])
        }

        let config = try AppConfig(infoDictionary: dictionary)

        #expect(config.apiBaseURL.absoluteString == raw)
        #expect(config.legal.terms.scheme == "https")
        #expect(config.legal.privacy.scheme == "https")
    }

    @Test("each configuration names its own Info.plist")
    func eachConfigurationNamesItsPlist() throws {
        for (name, plist) in Self.configurations {
            let setting = try #require(Self.settings(in: name)["INFOPLIST_FILE"])

            #expect(setting == "Configuration/\(plist)")
        }
    }

    // MARK: - The Info.plist files

    /// Every key `AppConfig` reads, and the build setting each is substituted from. A key added to the parse
    /// without being added here is a key the plists can be missing silently — which is a launch-time trap in a
    /// configuration nobody built locally.
    private static let plistKeys = [
        AppConfig.apiBaseURLKey: "$(HW_API_BASE_URL)",
        AppConfig.termsURLKey: "$(HW_TERMS_URL)",
        AppConfig.privacyURLKey: "$(HW_PRIVACY_URL)",
    ]

    @Test("every plist carries every key AppConfig reads", arguments: Self.plists)
    func everyPlistCarriesTheConfigurationKeys(_ plist: String) throws {
        let contents = try Self.plist(plist)

        for (key, setting) in Self.plistKeys {
            #expect(contents[key] as? String == setting, "\(plist) does not carry \(key)")
        }
    }

    /// And every setting the plists substitute is defined in every `.xcconfig`. A plist referring to a setting
    /// no configuration sets leaves the literal `$(…)` in the built app, which `AppConfig` then reports as
    /// malformed — at launch, in whichever configuration forgot.
    @Test("every configuration defines every setting the plists substitute", arguments: Self.names)
    func everyConfigurationDefinesEverySetting(_ configuration: String) throws {
        let settings = try Self.settings(in: configuration)

        for setting in Self.plistKeys.values {
            let name = String(setting.dropFirst(2).dropLast())
            #expect(settings[name] != nil, "\(configuration).xcconfig does not define \(name)")
        }
    }

    /// The two legal pages are **https in every configuration**, localhost included. `AppConfigTests` asserts the
    /// parse refuses cleartext; this asserts no checked-in configuration hands it any.
    @Test("every configuration's legal pages are https", arguments: Self.names)
    func everyConfigurationsLegalPagesAreSecure(_ configuration: String) throws {
        let settings = try Self.settings(in: configuration)

        for name in ["HW_TERMS_URL", "HW_PRIVACY_URL"] {
            let value = try #require(settings[name])
            #expect(value.hasPrefix("https://"), "\(configuration).xcconfig sets \(name) to \(value)")
        }
    }

    @Test("no plist turns App Transport Security off", arguments: Self.plists)
    func noPlistDisablesTransportSecurity(_ plist: String) throws {
        // `NSAllowsArbitraryLoads` exempts *every* host in the app, permanently, in whatever build it
        // ships in. For a finance app that is not a development convenience.
        let security = try Self.plist(plist)["NSAppTransportSecurity"] as? [String: Any] ?? [:]

        for key in security.keys {
            #expect(
                !key.hasPrefix("NSAllowsArbitrary"),
                "\(plist) sets \(key), which turns ATS off for hosts it does not name"
            )
        }
    }

    @Test("only the Debug plist excepts anything, and only localhost")
    func theExceptionIsScopedToLocalhost() throws {
        let debug = try Self.plist("Info-Debug.plist")["NSAppTransportSecurity"] as? [String: Any]
        let exceptions = try #require(debug?["NSExceptionDomains"] as? [String: Any])

        #expect(Array(exceptions.keys) == ["localhost"])
        #expect((exceptions["localhost"] as? [String: Any])?["NSExceptionAllowsInsecureHTTPLoads"] as? Bool == true)
    }

    @Test("the shipping plist has no exception at all")
    func theShippingPlistExceptsNothing() throws {
        // Not "an exception that happens to be harmless" — no `NSAppTransportSecurity` key, so there is
        // nothing in a shipped build for a later edit to widen.
        let keys = try Self.plist("Info.plist").keys

        #expect(!keys.contains("NSAppTransportSecurity"))
    }

    @Test("the two plists differ only in that exception")
    func thePlistsAgreeOnEverythingElse() throws {
        // The cost of two files is that they can drift. What keeps them honest is that the difference is
        // enumerated: one key, and it is the ATS dictionary.
        let shipping = try Set(Self.plist("Info.plist").keys)
        let debug = try Set(Self.plist("Info-Debug.plist").keys)

        #expect(debug.subtracting(shipping) == ["NSAppTransportSecurity"])
        #expect(shipping.subtracting(debug).isEmpty)
    }

    // MARK: - What the app runs on

    /// ADR-0001 — **iPhone only, portrait only, iOS 18.0, Swift 6.** All four are set in the project rather
    /// than in an `.xcconfig`, and all four are the kind of setting Xcode will happily widen for you: adding
    /// an iPad destination sets the device family, and a target created from a fresh template arrives with
    /// four orientations and whatever language mode is current.
    ///
    /// The criterion issue #5 stated is "already set in the project; assert it stays", and issue #10 asks for
    /// the same of the other two. So each is asserted as the absence of any *other* value rather than the
    /// presence of one: a fourth configuration that quietly allowed landscape would satisfy a presence check
    /// and fail this.
    ///
    /// This reads what the project file **says**. The workflow's `assert-build-settings.py` reads what
    /// `xcodebuild` **resolves**, in all three configurations — an `.xcconfig` or a command-line override sits
    /// between the two, and a disagreement is the bug worth catching (ADR-0028).
    @Test("the platform baseline is ADR-0001's, everywhere it is written")
    func thePlatformBaselineIsWhatWasDecided() throws {
        // Per-target settings appear once per target per configuration; the project-level ones once per
        // configuration. The minimum is stated rather than the exact count, because a new target is a
        // legitimate reason for there to be more and never a reason for there to be fewer.
        try expectEverySetting("TARGETED_DEVICE_FAMILY", equals: "1", atLeast: Self.names.count)
        try expectEverySetting(
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone",
            equals: "UIInterfaceOrientationPortrait",
            atLeast: Self.names.count
        )
        try expectEverySetting("IPHONEOS_DEPLOYMENT_TARGET", equals: "18.0", atLeast: Self.names.count)
        // Both targets, all three configurations — six. The app being on the Swift 6 language mode and the
        // test target not would be two languages in one repository.
        try expectEverySetting("SWIFT_VERSION", equals: "6.0", atLeast: 2 * Self.names.count)

        // And the value nobody sets on purpose: upside-down, which iOS offers on iPhone and which the
        // designs — fixed-height, bottom-anchored tab bar — were never drawn for.
        let project = try String(contentsOf: SourceTree.projectFile, encoding: .utf8)
        #expect(!project.contains("UIInterfaceOrientationPortraitUpsideDown"))
    }

    /// **The hole `INFOPLIST_KEY_*` leaves.** Those settings only reach the built app if the `Info.plist`
    /// does not already carry the key — an explicit entry wins. So a `UISupportedInterfaceOrientations` added
    /// to either plist would ship landscape with every check above still green.
    @Test("no Info.plist overrides the orientations the build settings decide", arguments: Self.plists)
    func noPlistOverridesTheOrientations(_ plist: String) throws {
        let keys = try Self.plist(plist).keys.filter { $0.hasPrefix("UISupportedInterfaceOrientations") }

        #expect(keys.isEmpty, "\(plist) sets \(keys), which wins over INFOPLIST_KEY_* and can widen it")
    }

    /// Every line in the project file that sets `key`, asserted to set it to `value` — with a floor on how
    /// many there are, since a scan that found none would pass while reading nothing.
    private func expectEverySetting(
        _ key: String,
        equals value: String,
        atLeast minimum: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let lines = try String(contentsOf: SourceTree.projectFile, encoding: .utf8)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix(key) }

        #expect(
            lines.count >= minimum,
            "\(key) is set in \(lines.count) places, fewer than the \(minimum) expected",
            sourceLocation: sourceLocation
        )
        #expect(
            lines.allSatisfy { $0 == "\(key) = \(value);" },
            "a configuration disagrees with ADR-0001 about \(key): \(lines)",
            sourceLocation: sourceLocation
        )
    }

    // MARK: - Reading the files

    /// The settings in one `.xcconfig`, comments removed and `$()` escapes resolved.
    ///
    /// `//` opens a comment in an .xcconfig, so a URL's scheme separator is written `http:/$()/…`. The
    /// comment is stripped **before** the escape is resolved, or resolving it would produce a `//` that
    /// then reads as a comment and swallows the host.
    private static func settings(in configuration: String) throws -> [String: String] {
        let file = SourceTree.configuration.appending(path: "\(configuration).xcconfig")
        let text = try String(contentsOf: file, encoding: .utf8)

        var settings: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let code = String(line).components(separatedBy: "//")[0]
            let parts = code.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, !parts[0].isEmpty else { continue }
            settings[parts[0]] = parts[1].replacingOccurrences(of: "$()", with: "")
        }
        // A file that parsed to nothing would make every assertion above pass without reading anything.
        guard !settings.isEmpty else { throw SourceTree.StructureError.unreadable(configuration) }
        return settings
    }

    private static func baseURL(in configuration: String) throws -> String {
        try #require(settings(in: configuration)["HW_API_BASE_URL"])
    }

    private static func plist(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: SourceTree.configuration.appending(path: name))
        let contents = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(contents as? [String: Any])
    }
}
