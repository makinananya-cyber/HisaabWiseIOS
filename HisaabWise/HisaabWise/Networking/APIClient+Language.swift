/// The client's half of the language bargain.
///
/// It already *reads* the choice on every request through `LanguageSource`; this is where it writes one
/// back. Both live on the same actor deliberately: the request that records the new language is also the
/// first request that carries it, so the response comes back formatted in the language the user just
/// asked for and a screen re-rendering from it is already correct (ADR-0020, ADR-0024).
///
/// An extension in `Networking` rather than a member of `LanguageManager`, because the protocol is in
/// `Models` and the dependency points downwards: `DesignSystem` never sees `APIClient`.
extension APIClient: LanguageSink {
    func setLanguage(_ language: AppLanguage) async throws -> AppLanguage {
        try await put(
            Endpoint.language,
            body: LanguagePreference(language: language),
            as: LanguagePreference.self
        )
        .language
    }
}

/// The body and the response both, because they are the same one field.
///
/// A wrapper object rather than the bare tag: `PUT /v1/me/language` answers with the updated screen
/// payload under ADR-0020, and a narrow `Decodable` reads its one field out of a wider body and ignores
/// the rest. So this shape stays right when the Account screen (#17) starts consuming the whole payload,
/// and it does not pre-empt what that payload looks like.
private struct LanguagePreference: Codable, Sendable {
    let language: AppLanguage
}
