# ADR-0030 — Sign in: one sentence for every refusal, and the appearance the vocabulary was waiting for

**Status:** accepted
**Extends:** [ADR-0007](0007-session-and-refresh.md) (which store a kept session goes to),
[ADR-0021](0021-two-surfaces-and-token-collapse.md) (the `brand` appearance now has its second caller),
[ADR-0029](0029-landing-conversion.md) (the brand ground, extracted here)
**Applies:** Product Spec §3.2 **[FIX]** ×2 — the identifier and the password rule
**Records a gap:** the erase date on `ACCOUNT_PENDING_DELETION` — see the last section

## Decision

**The identifier is the email, and the password rule is 8+.** The design asks for a username at sign-in and
registration never collects one, so there is nothing for a username to be; and its sign-in accepted six
characters where invariant 4 says eight everywhere. Both are asserted, the first by a scan that fails if the
word *username* reappears in either file.

**One sentence for every refusal.** `SignInFailure.credentialsRefused` is a single case, and the mapping is
**inverted on purpose**: everything from the login route is a refusal *unless it is a known fault* (5xx, 429,
400). The first version listed the refusal statuses instead — 401 and 403 — which left a `404 NO_SUCH_ACCOUNT`
falling through to its own copy and turned the form into an address checker. The faults are the ones a user
cannot cause, and they are the enumerable set.

**The client does not police the shape of an address.** Every regex is wrong about somebody's real email, and
the server checks it anyway. Emptiness is checked; shape is not.

**Three refusals suggest support, and nothing more.** The count never gates a request: server-side backoff is
authoritative, and a client that locked its own user out is a client a reinstall unlocks. A transport failure is
not counted — a tunnel is not a wrong password.

**The form's failure is a value.** `SignInFailure` knows which field it belongs beside, so "field-level errors"
is a property of the type rather than a layout decision, and `SignInView.copy(for:)` is the one place a failure
becomes words. This is the app's **second** owner of the `APIError` → presentation mapping, and
`StateTaxonomyTests` now names both: a *read* becomes a `LoadState` in `BaseViewModel.load()`, a *form* becomes
field errors here. A third would mean changing that list, which is the point.

**`SignInFailure.unreachable`, not `.offline`.** The word `offline` belongs to `LoadState`, and the taxonomy
scan keeps "only `StateView` switches on it" honest with a text scan for `case .offline`. The user reads the
same sentence — the copy is still `state.offline`.

**The screen holds its own view model**, unlike a tab's (issue #5). A tab keeps its state across a switch away
and back; a pushed form should lose it when the form goes — and here that is a security property as much as a
lifetime one, because the password lives in that object.

**Three components arrive, and one is extracted.** `HWCheckbox` (the design's `.check`, a checkbox rather than
a `Toggle`, because a switch means "this takes effect now" and this is part of a submission), `HWLink` (`.link`,
inline text with a 44pt target), and `HWTextField` gains the `brand` appearance plus secure entry with the
design's reveal eye. `HWBrandGround` is Landing's aurora, now that it has a second caller.

**The keyboard never capitalises or corrects either box.** iOS defaults to sentence case with autocorrect on,
which silently edits an email address — the identity — and a revealed password.

## Consequences

- **Successful sign-in navigates nowhere.** `isSignedIn` flips and `RootView` swaps Landing for the shell
  (ADR-0026), which is what "lands on Home" means here: one object changes and the root follows.
- Registration, password reset, and restore are `PreAuthRoute` cases with placeholder destinations, so every
  control on the screen goes somewhere. #15, #16, and #24 each replace one.
- **`ImageRenderer` cannot capture Landing or sign-in at all.** Their entrance stagger is gated on `onAppear`,
  which it does not run, so both come back as their own background — which means the "it renders" tests on those
  two screens prove that the `body` builds and nothing about what it looks like. A `UIHostingController` in a
  detached `UIWindow` was tried and is not enough either. Both screens were verified by screenshotting the
  running app; #9's baselines will need a capture inside a real scene, and this is the fourth thing in this app
  that needs one.
- The field label was invisible on brand in the first build: `hwLabel()` resolves the *surface* ink. Found by
  looking at the running app, which is now twice in two tickets.
- Not done, and not pretended: **no focus progression** between the two boxes (`submitLabel(.next)` and an
  `onSubmit` chain). The design has keyboard navigation in every form and this screen does not yet.

## The gap this ticket leaves

#14 asks that `ACCOUNT_PENDING_DELETION` be shown "with the erase date and the restore path". **The restore path
ships and the date does not.** The client decodes `{error:{code}}` and nothing else (ADR-0016), so reaching the
date means giving `APIError` a `details` bag — and a bag is how "the client never reads the server's prose"
erodes one field at a time. The code is handled distinctly, its copy is its own, and the date arrives with the
restore screen (#24), which owns the grace period. Recorded in `CONTEXT.md`'s table of changes this repo
requires elsewhere.
