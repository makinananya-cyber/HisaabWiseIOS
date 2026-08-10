import Foundation
@testable import HisaabWise
import Testing

/// The parse between a build configuration and a URL the client can use.
///
/// Every case here is a mistake someone makes in an `.xcconfig` once: a key that never got
/// substituted, a stray trailing slash, a host typed in `http` out of habit. The point of the type is
/// that each of them fails at launch with a sentence naming the file to fix, rather than becoming a
/// screen that says "you appear to be offline".
@Suite("AppConfig")
struct AppConfigTests {
    private func config(_ value: String) throws -> AppConfig {
        try AppConfig(infoDictionary: [AppConfig.apiBaseURLKey: value])
    }

    @Test("reads the base URL a configuration supplies")
    func readsTheBaseURL() throws {
        #expect(try config("https://api.example.com").apiBaseURL == URL(string: "https://api.example.com"))
    }

    @Test("keeps a port, because Debug is a port")
    func keepsAPort() throws {
        // The Debug configuration is `http://localhost:8787`. A parse that dropped the port would
        // point every local build at port 80 and read as "wrangler dev is not running".
        let url = try config("http://localhost:8787").apiBaseURL

        #expect(url.port == 8787)
        #expect(url.host() == "localhost")
    }

    @Test("keeps a base path, so a host that serves the API under a prefix works")
    func keepsABasePath() throws {
        #expect(try config("https://example.com/api").apiBaseURL.path() == "/api")
    }

    @Test("drops a trailing slash, which would otherwise compose into a double slash")
    func normalisesATrailingSlash() throws {
        // `https://api.example.com/` + `/v1/budget` is `//v1/budget`, which some routers treat as a
        // different route and others as a 404. The configuration's author should not have to know.
        let url = try config("https://api.example.com//").apiBaseURL

        #expect(url.appending(path: "/v1/budget").absoluteString == "https://api.example.com/v1/budget")
    }

    @Test("reports a missing key rather than falling back to a default")
    func missingKeyIsAnError() {
        // ADR-0010 — there is no default base URL anywhere in the app, and Rule 7 forbids inventing
        // one. A build that did not say where the API is has to say so.
        #expect(throws: AppConfig.ConfigurationError.missing(key: AppConfig.apiBaseURLKey)) {
            try AppConfig(infoDictionary: [:])
        }
    }

    @Test("reports a blank value as missing, not as malformed")
    func blankValueIsMissing() {
        #expect(throws: AppConfig.ConfigurationError.missing(key: AppConfig.apiBaseURLKey)) {
            try config("   ")
        }
    }

    @Test("reports a value of the wrong type as malformed, naming what it found")
    func wrongTypeIsMalformed() {
        // Distinct from missing on purpose: the key is there, so the fix is the value's *shape* — a
        // number where a string belongs, which is what an unquoted plist entry produces.
        #expect(
            throws: AppConfig.ConfigurationError.malformed(key: AppConfig.apiBaseURLKey, value: "8787")
        ) {
            try AppConfig(infoDictionary: [AppConfig.apiBaseURLKey: 8787])
        }
    }

    @Test("catches an unsubstituted build setting")
    func unsubstitutedSettingIsMalformed() {
        // The literal shape an `Info.plist` takes when `HW_API_BASE_URL` is undefined — the single most
        // likely failure when a fourth configuration gets added and its `.xcconfig` is forgotten.
        let unsubstituted = "$(HW_API_BASE_URL)"

        #expect(
            throws: AppConfig.ConfigurationError.malformed(
                key: AppConfig.apiBaseURLKey,
                value: unsubstituted
            )
        ) {
            try config(unsubstituted)
        }
    }

    @Test("rejects a value with no scheme")
    func schemeIsRequired() {
        #expect(
            throws: AppConfig.ConfigurationError.malformed(
                key: AppConfig.apiBaseURLKey,
                value: "api.example.com"
            )
        ) {
            try config("api.example.com")
        }
    }

    @Test("accepts cleartext for localhost, which is what wrangler dev serves")
    func cleartextLocalhostIsAccepted() throws {
        #expect(try config("http://localhost:8787").apiBaseURL.scheme == "http")
    }

    @Test("refuses cleartext for any other host")
    func cleartextElsewhereIsRefused() {
        // The ATS exception in the Debug `Info.plist` names `localhost` and nothing else, so a
        // cleartext URL for another host is a configuration the app would accept and then App
        // Transport Security would refuse — which reads to a developer as "the server is down".
        // Refusing it here names the actual problem (ADR-0010).
        #expect(
            throws: AppConfig.ConfigurationError.insecure(scheme: "http", host: "api.example.com")
        ) {
            try config("http://api.example.com")
        }
    }

    @Test("is not fooled by an uppercase scheme")
    func schemeComparisonIsCaseInsensitive() throws {
        #expect(try config("HTTPS://api.example.com").apiBaseURL.host() == "api.example.com")
    }

    @Test("refuses a scheme that is neither http nor https")
    func otherSchemesAreRefused() {
        // A custom scheme is what ADR-0010 rejected for email links; it has no business being a base
        // URL either.
        #expect(throws: AppConfig.ConfigurationError.insecure(scheme: "hisaabwise", host: "api")) {
            try config("hisaabwise://api")
        }
    }
}
