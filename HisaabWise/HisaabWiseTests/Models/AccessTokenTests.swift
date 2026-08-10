import Foundation
@testable import HisaabWise
import Testing

/// The claims the client reads off an access token, and the refusals that keep it from reading a token
/// it cannot schedule a refresh for.
@Suite("AccessToken")
struct AccessTokenTests {
    @Test("reads the expiry out of the JWT rather than out of a field beside it")
    func readsTheExpiryClaim() throws {
        let token = try AccessToken(raw: TestBench.accessToken(expiresIn: 900))

        // Close to fifteen minutes from now: the fixture stamps `exp` from the clock, so the assertion is on
        // the parse, not on the arithmetic.
        //
        // The tolerance has to exceed **one** second, not equal it. `exp` is a whole number of seconds, so
        // `Int(...)` truncates up to a second of the sub-second offset the clock happened to be at, and the
        // measured difference reaches 1.0 on its own without anything being slow. `< 1` was therefore a
        // coin-flip against the wall clock rather than a bound on the parse.
        #expect(abs(token.expiresAt.timeIntervalSinceNow - 900) < 2)
    }

    @Test("reads the sec claim, which is what makes a securityEpoch bump visible at all")
    func readsTheSecurityEpochClaim() throws {
        // Backend ADR-0005 mints the user's `securityEpoch` into every access token as `sec`.
        let token = try AccessToken(raw: TestBench.accessToken(securityEpoch: 7))

        #expect(token.securityEpoch == 7)
    }

    @Test("accepts a token with no sec claim rather than refusing one over a claim it only reads")
    func toleratesAMissingSecurityEpoch() throws {
        // The server compares the epoch; the client only reports it. Refusing a token here would make
        // the client the authority on something it is not (invariant 10).
        let token = try AccessToken(raw: TestBench.accessToken(securityEpoch: nil))

        #expect(token.securityEpoch == nil)
        #expect(token.expiresAt.timeIntervalSinceNow > 0)
    }

    @Test("keeps the token exactly as issued, because that is what goes on the wire")
    func keepsTheRawToken() throws {
        let raw = TestBench.accessToken()

        #expect(try AccessToken(raw: raw).raw == raw)
    }

    @Test("refuses a string that is not a JWT")
    func refusesANonJWT() {
        // The wiring mistake this catches: an opaque token, or a field read from the wrong key. Carrying
        // it as an opaque string would trade a loud failure at sign-in for a silent logout later.
        #expect(throws: AccessTokenError.notAJWT) { try AccessToken(raw: "opaque-token") }
    }

    @Test("refuses a real JWT whose payload has no expiry")
    func refusesAJWTWithoutAnExpiry() {
        // Three well-formed segments, claims that are not the ones agreed. Distinguished from `notAJWT`
        // because the two are different bugs on different sides of the contract.
        let payload = Data(#"{"sub":"user_1"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")

        #expect(throws: AccessTokenError.noExpiry) { try AccessToken(raw: "header.\(payload).signature") }
    }

    // MARK: - The refresh window

    @Test("counts a token with under a minute left as near expiry")
    func aTokenWithUnderAMinuteIsNearExpiry() throws {
        // ADR-0007 — proactive refresh fires under roughly 60s of remaining life, which is what keeps the
        // 401 path rare rather than routine.
        let token = try AccessToken(raw: TestBench.accessToken(expiresIn: 30))

        #expect(token.isNearExpiry())
    }

    @Test("counts a fresh token as not near expiry")
    func aFreshTokenIsNotNearExpiry() throws {
        let token = try AccessToken(raw: TestBench.accessToken(expiresIn: 900))

        #expect(!token.isNearExpiry())
    }

    @Test("counts an expired token as near expiry, not as some other state")
    func anExpiredTokenIsNearExpiry() throws {
        // One question, not two. A dead token and a nearly-dead one are both answered by refreshing, and
        // a second predicate would be a second thing for a call site to forget.
        let token = try AccessToken(raw: TestBench.accessToken(expiresIn: -60))

        #expect(token.isNearExpiry())
    }

    @Test("takes the moment it is asked about, so the window is not the wall clock")
    func theWindowIsMeasuredAgainstAGivenMoment() throws {
        let token = try AccessToken(raw: TestBench.accessToken(expiresIn: 900))

        #expect(!token.isNearExpiry(at: token.expiresAt.addingTimeInterval(-120)))
        #expect(token.isNearExpiry(at: token.expiresAt.addingTimeInterval(-30)))
    }

    // MARK: - Decoding

    @Test("decodes from the bare string the server sends")
    func decodesFromAString() throws {
        let raw = TestBench.accessToken()
        let body = TestBench.tokenPair(access: raw, refresh: "refresh-1")

        let tokens = try JSONDecoder().decode(SessionTokens.self, from: body)

        #expect(tokens.accessToken.raw == raw)
        #expect(tokens.refreshToken == "refresh-1")
    }

    @Test("a malformed token fails decoding, so it reads as a malformed response")
    func aMalformedTokenFailsDecoding() {
        let body = TestBench.tokenPair(access: "not-a-jwt", refresh: "refresh-1")

        #expect(throws: (any Error).self) { try JSONDecoder().decode(SessionTokens.self, from: body) }
    }
}
