# ADR-0010 — Base URL from `.xcconfig`; auth email links are web-first

**Status:** accepted
**Amends:** Technical Spec §5 (`POST /v1/auth/reset-password` must be callable from a web form)

## Context

Rule 7 requires the iOS app to read its API base URL from configuration, never a hardcoded host,
so that pointing it at a real domain later is a config change. The domain itself is still an open
point in `DEVELOPMENT_PLAN.md` §7.

Phase 1 ships email verification and password reset (§3.2, defect D7), both of which arrive as
links in an email. Universal links require an `apple-app-site-association` file served from the
domain — which does not exist, and which Rule 7 defers until Cloudflare credentials arrive. So the
email flows would be blocked on infrastructure if they depended on the app opening the link.

## Decision

**Configuration.** Three build configurations — Debug → `http://localhost:8787` (`wrangler dev`),
Staging, Release — each feeding an `Info.plist` key, read **once** into an `AppConfig` in the app
shell and injected into `HWNetworking` at the composition root. `HWNetworking` has no notion of
environments. The ATS exception is scoped to localhost only; never `NSAllowsArbitraryLoads`.

**Email links are web-first.** Verification and reset links open a hosted page on the marketing
site that completes the flow end to end. The app picks up the new state at its next foreground
`GET /v1/me` revalidation (ADR-0008). When the domain and an AASA file land, **the same emails
begin opening the app** — configuration, not an email-template change.

## Consequences

- Phase 1's email flows are unblocked with no domain and no AASA file, which is exactly the shape
  Rule 7 asks for.
- Requires `POST /v1/auth/reset-password` to be callable from a browser form, not only from the
  app. This is a real backend requirement, listed in `CONTEXT.md`.
- `HWNetworking` having no environment awareness is what lets tests inject a base URL without a
  build configuration.
- **Rejected:** a custom URL scheme (`hisaabwise://`). It works today with no domain, but any
  installed app can claim the same scheme, and many mail clients mangle it. For a finance app's
  password-reset link that is a security regression, not a shortcut.
