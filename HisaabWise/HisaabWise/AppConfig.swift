import Foundation

/// What the build configuration told the app, read once at launch.
///
/// ADR-0010's shape, exactly: three `.xcconfig` files feed one `Info.plist` key per configuration,
/// this type parses it, and the composition root injects the result. **It lives at the app root and
/// not in `Networking/`** — knowing that a build has environments is precisely what the networking
/// layer must not know, and a scan in `LayeringTests` keeps it out.
///
/// It takes the **`Info.plist` dictionary**, not a `Bundle`. `Bundle.main` is environment awareness of
/// a different kind — it is "the app I happen to be running inside" — and having it in here would mean
/// the malformed cases below could only be tested by building a deliberately broken app. The root
/// reads the dictionary; this parses it.
struct AppConfig: Sendable, Equatable {
    /// The `Info.plist` key carrying `$(HW_API_BASE_URL)`. One name, spelled here and in the two
    /// plists in `Configuration/`, and asserted against them by `BuildConfigurationTests`.
    static let apiBaseURLKey = "HWAPIBaseURL"

    /// The `Info.plist` keys carrying the two hosted legal pages, `$(HW_TERMS_URL)` and
    /// `$(HW_PRIVACY_URL)`.
    ///
    /// **Configuration rather than constants**, for the same reason the API base URL is (ADR-0010, Rule 7): the
    /// domain does not exist yet, and a hardcoded host would be one more place to edit when it does. They also
    /// have to be able to differ per environment — a staging build linking to the production Terms is a build
    /// that cannot be used to review a change to them.
    static let termsURLKey = "HWTermsURL"
    static let privacyURLKey = "HWPrivacyURL"

    /// Where `/v1` hangs off. Handed to `APIClient` at the composition root and nowhere else.
    let apiBaseURL: URL

    /// The two pages the registration consent checkbox links to (#15), and the Account screen will (#17).
    let legal: LegalLinks

    init(infoDictionary: [String: Any]) throws {
        let raw = try Self.string(infoDictionary, key: Self.apiBaseURLKey)

        // A trailing slash on the base and a leading slash on every path would compose into `//v1`,
        // which some routers treat as a different route and others as a 404. Normalised here so the
        // configuration file's author does not have to know.
        var normalised = raw
        while normalised.hasSuffix("/") {
            normalised.removeLast()
        }

        guard let url = URL(string: normalised),
              let scheme = url.scheme?.lowercased(),
              let host = url.host()
        else {
            // Also the shape an *unsubstituted* setting takes: a missing `HW_API_BASE_URL` leaves the
            // literal `$(HW_API_BASE_URL)` in the plist, which has neither a scheme nor a host.
            throw ConfigurationError.malformed(key: Self.apiBaseURLKey, value: normalised)
        }

        guard scheme == "https" || (scheme == "http" && host == Self.cleartextHost) else {
            throw ConfigurationError.insecure(key: Self.apiBaseURLKey, scheme: scheme, host: host)
        }

        apiBaseURL = url

        // The legal pages are **https-only, with no localhost exception**. The API has one because a Debug build
        // talks to `wrangler dev`; nothing serves Terms & Privacy locally, and an http link would be a cleartext
        // page ATS refuses at the moment the user taps it.
        legal = LegalLinks(
            terms: try Self.httpsURL(infoDictionary, key: Self.termsURLKey),
            privacy: try Self.httpsURL(infoDictionary, key: Self.privacyURLKey)
        )
    }

    /// One key's value as a non-blank string.
    ///
    /// A key present and blank is the same statement as a key absent: this build did not say. Both read as
    /// missing so the message names the fix rather than the symptom.
    private static func string(_ infoDictionary: [String: Any], key: String) throws -> String {
        guard let value = infoDictionary[key] else {
            throw ConfigurationError.missing(key: key)
        }
        guard let raw = value as? String else {
            throw ConfigurationError.malformed(key: key, value: String(describing: value))
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ConfigurationError.missing(key: key)
        }
        return trimmed
    }

    /// One key's value as an `https` URL, or a thrown error naming which key was wrong and how.
    private static func httpsURL(_ infoDictionary: [String: Any], key: String) throws -> URL {
        let raw = try string(infoDictionary, key: key)
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), let host = url.host() else {
            // Also the shape an *unsubstituted* setting takes: a missing build setting leaves the literal
            // `$(HW_TERMS_URL)` in the plist, which has neither a scheme nor a host.
            throw ConfigurationError.malformed(key: key, value: raw)
        }
        guard scheme == "https" else {
            throw ConfigurationError.insecure(key: key, scheme: scheme, host: host)
        }
        return url
    }

    /// The only host the app will talk to in cleartext, and the same one the Debug `Info.plist`'s ATS
    /// exception names. The two have to agree: a cleartext URL for any other host would be a
    /// configuration the app accepts and then App Transport Security refuses, which reads to a
    /// developer as "the server is down" (ADR-0010).
    private static let cleartextHost = "localhost"

    /// Why a build configuration could not be read. Each case names what to fix in the `.xcconfig`.
    enum ConfigurationError: Error, Equatable {
        /// The key is absent, or present and blank.
        case missing(key: String)
        /// The value is not a string, or not a URL with a scheme and a host.
        case malformed(key: String, value: String)
        /// The value is cleartext HTTP where the key does not allow it. **It names the key**: three of the four
        /// settings are URLs, and an error that said only "http, localhost" left the reader to guess which one.
        case insecure(key: String, scheme: String, host: String)
    }
}
