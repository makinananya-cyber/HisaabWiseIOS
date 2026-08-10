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

    @Test("Debug points at wrangler dev on the loopback interface")
    func debugPointsAtWranglerDev() throws {
        // The exact value, not merely "a localhost URL": the port is what the backend serves on, and a
        // parse that lost it reads as "wrangler dev is not running".
        #expect(try Self.baseURL(in: "Debug") == "http://localhost:8787")
    }

    @Test("staging and production are HTTPS", arguments: Self.deployedNames)
    func deployedConfigurationsAreEncrypted(_ configuration: String) throws {
        #expect(try Self.baseURL(in: configuration).hasPrefix("https://"))
    }

    @Test("every configuration's base URL is one the app will accept", arguments: Self.names)
    func everyBaseURLParses(_ configuration: String) throws {
        // End to end against the real parser, so a value that would trap at launch fails here instead:
        // ``AppConfig`` refuses cleartext for anything but localhost, and refuses a URL with no scheme —
        // which is the shape a forgotten `$()` escape leaves behind, since `//` opens a comment in an
        // .xcconfig and would truncate the value to `http:`.
        let raw = try Self.baseURL(in: configuration)

        let config = try AppConfig(infoDictionary: [AppConfig.apiBaseURLKey: raw])

        #expect(config.apiBaseURL.absoluteString == raw)
    }

    @Test("each configuration names its own Info.plist")
    func eachConfigurationNamesItsPlist() throws {
        for (name, plist) in Self.configurations {
            let setting = try #require(Self.settings(in: name)["INFOPLIST_FILE"])

            #expect(setting == "Configuration/\(plist)")
        }
    }

    // MARK: - The Info.plist files

    @Test("every plist carries the key AppConfig reads", arguments: Self.plists)
    func everyPlistCarriesTheBaseURLKey(_ plist: String) throws {
        let contents = try Self.plist(plist)

        #expect(contents[AppConfig.apiBaseURLKey] as? String == "$(HW_API_BASE_URL)")
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
