# ADR-0005 — One write queue; the client-generated UUID is the only idempotency key

**Status:** accepted
**Amends:** Technical Spec §5 (`DELETE /v1/expenses/:id` must be idempotent; the
`Idempotency-Key` header is not used by this client)

## Context

ADR-0004 and ADR-0006 together mean the queue carries two unrelated kinds of write: expense
entries and lesson completions. Writing the retry, ordering, and failure machinery twice is the
obvious mistake.

There is also a live inconsistency to resolve from the client side. Technical Spec §5 says
`POST /v1/expenses` accepts an `Idempotency-Key` header, while §4 says the **client-supplied
UUID `_id` is** the mechanism, "so no key store is needed (ADR-0011)". Sending both would give
one write two keys that can disagree.

## Decision

**One SwiftData table** — `PendingWrite { id: UUID, kind, payload: Data, createdAt, attempts,
lastError }` — drained in `createdAt` order. Kinds: `createExpense`, `deleteExpense`,
`completeLesson`.

**The UUID is the only idempotency key.** The client generates the entry's UUID at log time and
sends it as `_id`. The `Idempotency-Key` header is vestigial under backend ADR-0011 and is not
sent.

**Failure semantics, by kind:**

- `MONTH_CLOSED` on an expense → offer re-filing into the live month, showing the **true** date
  rather than lying about it (§4.5).
- `422` on a lesson completion → **terminal**. A rejected submission is a poison message;
  retrying it forever is the bug.
- `404` on a delete → **success**. Requires the endpoint to be explicitly idempotent, or a
  retried delete never drains.
- Everything else → exponential backoff with a cap. After repeated failure the pending badge
  escalates to "couldn't sync — tap for details" rather than retrying invisibly.

**Delete is optimistic, on two paths.** Deleting a *pending* entry drops it from the queue and
never touches the network. Deleting a *synced* entry enqueues `deleteExpense` and hides the row
immediately, with a brief undo. No confirmation dialog on a single expense line — it is
low-stakes and re-entry takes seconds.

## Consequences

- Ordering, backoff, and poison-message handling exist once, and a lesson completion cannot be
  starved by a failing expense or vice versa.
- The two idempotency mechanisms can never disagree, because only one is ever sent.
- ADR-0006's local unlock check exists to stop the queue generating guaranteed `422`s.
- `DELETE /v1/expenses/:id` returning `404` for an already-deleted id must be treated as success
  by contract, not by client guesswork — this is a real requirement on the backend, listed in
  `CONTEXT.md`.
