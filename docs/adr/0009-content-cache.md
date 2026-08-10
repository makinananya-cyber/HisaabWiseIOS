# ADR-0009 — Offline-critical content is an explicit on-disk store, not `URLCache`

**Status:** accepted

## Context

ADR-0006 promises offline lessons, and Product Spec §6 forbids compiling content into the app
binary. So the availability of curriculum while offline is a **guarantee the client makes**, not a
performance nicety.

`URLCache` is the cheap route — URLSession handles `ETag`/`If-None-Match` revalidation for free —
but it can evict entries under memory or disk pressure and offers no guarantee that a given
response is still there. Betting an offline promise on a cache *hint* is the wrong trade.

## Decision

**Split by criticality.**

Offline-critical — curriculum, picklists, categories, and the reference lists (countries,
currencies, languages) — are **JSON files in Application Support**, each with a metadata record
holding `etag`, `fetchedAt`, and `contentVersion`. `If-None-Match` is sent manually and a `304`
means keep what is on disk.

Non-critical — tips and articles — ride `URLCache`, where staleness is harmless.

Fetched eagerly after the first successful authentication (ADR-0004), revalidated per ADR-0008,
and marked `isExcludedFromBackup` since everything is re-fetchable.

**Files, not SwiftData rows.** These are large opaque blobs; SwiftData would add migration risk
and buy nothing — there is nothing to query.

## Consequences

- The ETag maps to the Worker's bundled content version (backend ADR-0008), so it changes exactly
  on deploy and never spuriously.
- Answer keys sit in plaintext on the device. That is a conscious choice already made in §6, and
  writing them to a file rather than a database does not change it.
- Excluding the store from backup keeps a user's iCloud backup small and means a restored device
  re-fetches current content rather than replaying stale content with a stale ETag.
- A first launch that never reaches the network has no curriculum at all — handled explicitly by
  ADR-0004's "lessons not downloaded yet" state.
