# ADR-0023 — The session's shape: an authorization property, expiry from the JWT, and a root-level owner

**Status:** accepted
**Refines:** [ADR-0007](0007-session-and-refresh.md) (storage and single-flight), [ADR-0008](0008-app-lifecycle.md) (the foreground sequence), [ADR-0022](0022-production-transport.md) (what every request carries)
**Context for:** issue #4, and #5 · #14 · #17, which are the first callers

## Context

ADR-0007 decided *where the refresh token lives* and *that refresh is single-flight*. Building it
surfaced six decisions it did not cover, each with a plausible wrong answer that no test would have
caught — and one gap that is not this repo's to close: **the backend has no `/v1/auth/*` routes yet**,
so the wire contract had to be written down by the side that could.

## Decision

### The auth contract the client is built against

Four shapes, recorded here because the client is now the only place they exist. They are a
**commitment**, listed in `CONTEXT.md`'s outside-this-repo table.

```
POST /v1/auth/login    {email, password, timeZone}   → 200 {accessToken, refreshToken}
POST /v1/auth/refresh  {refreshToken, timeZone}      → 200 {accessToken, refreshToken}
POST /v1/auth/logout   {refreshToken}                → 200 {}          (authenticated)
GET  /v1/me                                          → 200 {email, displayName, emailVerified}
```

Two details in there are decisions rather than transcription:

**A refresh returns a new refresh token, not just an access token.** Rotation revokes the presented
one (backend ADR-0005), so a response modelled as "access token only" is how a client ends up
presenting a revoked token and having the family revoked under it.

**`timeZone` on both login and refresh.** Invariant 6 makes day boundaries server-owned and computed
in the user's *stored* IANA timezone, "captured from the device at login and refresh". Those two
requests are therefore the only two places the capture can happen, and without the field it never
happens after registration.

**`GET /v1/me` carries identity, not figures.** Salary, display currency, and every derived
percentage reach a screen through that screen's own endpoint (ADR-0020). Duplicating them here would
give invariant 2's single owner a second copy that a stale revalidation could disagree with. What
`/v1/me` does carry is what changes *outside* the app and has no screen to arrive through —
`emailVerified` flips when the user taps a link in Mail and verifies in Safari (ADR-0010), and this
response is what clears the banner on return.

### The access token's expiry comes out of the JWT, not out of a field beside it

The client has to open the payload anyway: ADR-0007's proactive refresh needs to know when the token
dies, and the `sec` claim is what makes a `securityEpoch` bump visible at all. Reading `exp` from the
same place removes the second copy of one fact — and with it the failure mode where a server that
changes its token lifetime forgets to change the field next to it.

**A token the client cannot parse is a malformed response**, thrown at decode time rather than
carried as an opaque string. The alternative trades a loud failure at sign-in for a silent logout
fifteen minutes later.

**Nothing in this is a security check.** The signature is not verified and cannot be — the client
holds no key — and the claims are read to schedule a refresh. The server rejects a token it does not
like whatever the client believes about it (invariant 10).

### `sec` is *presented*, and a 401 is what makes the bump prompt

The `sec` claim rides along in the token, which is why the client sends the token **exactly as
issued** rather than a re-encoding of the claims it happens to read. But presenting it is not what
makes a `securityEpoch` bump a prompt sign-out — this is:

**A 401 triggers a refresh even when the clock says the token is fresh.** A client that refreshed
only on `exp` would keep presenting a token the server has already invalidated, for up to fifteen
minutes of failures, after a password change or a "sign out other devices" elsewhere. Refreshing on
the *server's* answer rather than only on the clock is what makes the response prompt; the refresh
then fails definitively, and the user is signed out.

### Authorization is a property of the request, defaulting to `session`

Two cases — `.session` and `.anonymous` — rather than a path list. ADR-0022 rejected a per-endpoint
table for `Idempotency-Key` because a table falls out of step with the routes, and the same holds
here with an extra edge: **`POST /v1/auth/logout` is an auth route that does need the session**, so a
`/v1/auth/` prefix rule would be wrong on its first exception.

The default is `.session`, because the mistake a default must make impossible is forgetting to
authenticate a per-user route. The cost in the other direction — a bearer token on a route that
ignores it — is nothing.

**The client does not gate a request on its own belief about whether it has a session.** With no
token it sends none and lets the server answer, which keeps a signed-out request reaching the
transport and failing honestly rather than failing on a guess (invariant 10).

### Which store a session goes to is decided at sign-in, by the coordinator

The client is *constructed* with the persistent store, because that is the one a launch has to
consult to find a session at all. Which store a **new** session goes to is the checkbox's decision,
so `beginSession(_:storingRefreshTokenIn:)` takes it — and clears the store it is leaving behind,
because signing in with the box unchecked after previously checking it must not leave a live 60-day
credential in the Keychain for a session the user asked not to keep.

`beginSession` is non-throwing. A Keychain that refuses the write costs the user persistence across
launches; failing a sign-in that has *already succeeded* on the server would cost them the session
too, and would make a storage problem look like a credentials problem.

### The three failure branches, kept distinct

ADR-0007 named two. There are three, and collapsing any pair reintroduces the bug from one side or
the other:

| On refresh | Outcome | Session |
|---|---|---|
| `401` | hard logout, store cleared, `sessionEnded` yields | over |
| transport failure | `offline` | **kept** |
| anything else (`5xx`, undecodable) | the server error, unchanged | **kept** |
| the store cannot be *read* | `offline` | **kept** |

The fourth row is the one ADR-0007 implies and does not state. A Keychain protected by
`AfterFirstUnlock` cannot be read before the first unlock after a reboot; treating that as "no
session" would sign the user out for having restarted their phone. It is exactly why
`TokenStore.refreshToken()` is allowed to throw rather than simply returning `nil`.

`APIError` gains **one** case, `unauthenticated`, for "this request needed a session and there is
none left". Its own case rather than a fabricated `server(status: 401, …)`, because in half of the
cases it covers no server was asked.

### The session owner lives at the app root, and maps no errors

`SessionCoordinator` sits beside `AppEnvironment` and `AppConfig` rather than in a layer. It owns no
screen, so it is not a view model, and every layer below it would be the wrong home for something the
whole app reads.

**It maps no `APIError` to anything, and the scans make that structural.**
`StateTaxonomyTests` allows `APIError` in exactly two places, and this is not one of them — which
turned out to be the right pressure rather than an obstacle: what the coordinator needs from a failed
request is not a state to render but the answer to "is there still a session", which it asks the
client. A screen renders the failure; the coordinator decides who is signed in.

**A hard logout is published as an `AsyncStream`, not as an injected callback.** A collaborator handed
to the client would be a second seam, and tests would start exercising a double of our own design
(ADR-0013). The coordinator's *own* requests do not rely on the stream at all — they reconcile with
`client.hasSession` afterwards, which is what makes the common path deterministic; the stream covers a
revocation discovered by whichever screen's request happened to be in flight.

## Consequences

- **`endSession` refreshes before it revokes, and then bypasses the retry path.** Reading the stored
  token first would hand the revoke a token the refresh underneath it had just rotated away: the
  server refuses it, the *new* refresh token stays valid for 60 days, and the logout reports success
  having revoked nothing. And the revoke is sent without the refresh-on-401 machinery, because a `401`
  there means the server had already ended the session — going through the retry path would refresh,
  find the family revoked, and **signal a hard logout for a logout the user asked for**.
- **The remote revoke is best-effort.** A user who taps "log out" on a dead network has still logged
  out; leaving them signed in until the network returns would be the app arguing with them.
- **The refresh `POST` is keyed like every other one** (ADR-0022), even though it does not go through
  `post()`. It is in fact the `POST` that rule was written for: a refresh that reached the server and
  whose response was lost would, retried without a key, present a token the server has already spent —
  and reuse revokes the family. A test asserts the header, because the route bypasses the verb method
  that would otherwise guarantee it.
- **The Keychain has exactly one caller, and that is scanned.** An item written from anywhere else
  would carry whatever accessibility class that call site picked, and the attribute assertions would
  still be green. The scan is also the unconditional half of "unchecked leaves nothing behind": the
  round-trip proof that an in-memory store writes nothing can only run where there *is* a writable
  Keychain.
- **`FixtureTransport` can hold the first N requests until all N have arrived.** The single-flight test
  needs three requests genuinely in flight at once; without that they may serialise, the second then
  legitimately presents the token the first refreshed into, and the test passes or fails on the
  scheduler rather than on behaviour.
- **`.unauthenticated` renders as `failed` for the moment it is on screen**, because it arrives with
  the session already ended and Landing is next. A fifth `LoadState` case would add a state every
  screen has to handle and none can act on.
- **Neither branch of single-flight is reachable on demand from a test.** A caller whose `401` returns
  mid-refresh joins the shared task; one whose `401` returns after it landed finds its token already
  replaced and retries. The scheduler picks, so the assertion is the one property true of both —
  *exactly one refresh reaches the transport* — rather than a test per branch.
- **`FixtureTransport` gained per-path sequences.** Its global `queue` cannot serve concurrent
  callers: the order requests reach the transport is not the order the test wrote them in, so a global
  queue answers the wrong caller.
- **The Keychain attributes are asserted on the query the store builds, not on a saved item.** The
  simulator stamps every item with an access group, so a readback could never prove the *absence* of
  one — which is a third of the decision.
- **Two new scans.** `Persistence/` may not name the access token, and no view, component, or view
  model may name a token at all. Both are ADR-0007 invariants that nothing else would catch.
- **Foreground handling is wired at the composition root for now**, since `onForeground()` is a method
  and something has to observe `scenePhase` to call it. Issue #5 takes it over along with the privacy
  overlay, which needs the same observer.
- **Rejected:** a `keepMeSignedIn: Bool` on the client, with the client choosing a store. It would put
  the Keychain decision inside `Networking/` and make ADR-0007's seam a branch instead of two
  conformances — and O3's app lock would then be an edit rather than a third conformance.
- **Rejected:** gating authenticated requests on `hasSession` before sending. It reads as a
  safeguard and is really the client deciding something the server decides, and it makes every
  signed-out request fail without leaving a trace at the transport for anyone debugging it.
