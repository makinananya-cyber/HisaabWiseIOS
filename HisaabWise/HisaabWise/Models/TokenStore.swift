/// Where the refresh token lives.
///
/// ADR-0007 — the seam behind "Keep me signed in". Checked stores the token in the Keychain and the
/// session survives a relaunch; unchecked keeps it in memory and the session ends with the process.
/// Both are conformances rather than a branch inside one store, so O3's app lock becomes a third
/// conformance rather than a refactor of the first two.
///
/// **The access token is deliberately not here.** It is held in memory by the client and never
/// persisted (ADR-0007), so a store that could hold one would be a store someone eventually does.
///
/// `async` and `throws` on every member even though the Keychain is synchronous and in-memory cannot
/// fail: the app-lock conformance would need to await a biometric prompt, and a protocol that has to
/// gain `async` later is a protocol every call site has to be revisited for.
protocol TokenStore: Sendable {
    /// The stored refresh token, or `nil` when there is no session to restore.
    ///
    /// - Throws: when the store could not be *read*, which is not the same as being empty. A Keychain
    ///   protected by `AfterFirstUnlock` cannot be read before the first unlock after a reboot, and
    ///   treating that as "no session" would sign the user out for having restarted their phone.
    func refreshToken() async throws -> String?

    func save(refreshToken: String) async throws

    /// Removes the stored token. Succeeds when there was nothing there.
    func clear() async throws
}
