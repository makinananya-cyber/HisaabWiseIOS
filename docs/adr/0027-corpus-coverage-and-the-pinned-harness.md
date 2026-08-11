# ADR-0027 — Corpus coverage is derived from the source, and the snapshot harness waits on a GUI step

**Status:** accepted
**Extends:** [ADR-0013](0013-testing-and-previews.md) (which decided *that* tests and previews share one
corpus of HTTP payloads, and that the snapshot suite is thin and pinned — not how coverage is checked or what
"pinned" is in code)
**Blocked, and recorded rather than deferred quietly:** `swift-snapshot-testing` cannot be added to this
project from the command line — see the last section

## Context

ADR-0013's argument is that one corpus with two consumers makes a drifted fixture break a test rather than rot
a preview. Issue #9 asks for that corpus to cover "every endpoint the screen tickets consume", for a snapshot
suite of exactly four cases, and for the device and runtime to be pinned. Four questions follow.

**What "covers every endpoint" can mean today.** Six of the endpoints ADR-0020 commits to do not exist — not
in the client, not in the backend, and their payload shapes are what the screen tickets will decide. A fixture
for one of those would be a guess at a contract, which is exactly what issue #5 refused to put in the client
for the unwritten tabs.

**How coverage stays true.** A list of endpoints in a test is a list somebody has to remember to extend, and
the failure mode is a green suite.

**What "pinned" is, as code.** Pixels are a function of the whole stack: a different simulator has a different
screen, a different runtime renders the same SwiftUI differently. Baselines recorded on one and compared on
another fail for reasons that are nobody's bug — and a flaky gate gets deleted rather than fixed, which
ADR-0013 says in as many words.

**Whether drift is actually exercised.** "A drifted fixture breaks a test" was a claim with nothing behind it:
no fixture had drifted.

## Decision

**The corpus covers every endpoint the app *calls*, and the check reads `Endpoint.swift`.** Each fixture
declares the paths it answers (`Fixture.endpoints`); `FixtureCorpusTests` extracts every `/v1` literal from
the source and requires each to be claimed. When a screen ticket adds `GET /v1/screens/expenses`, the test asks
for its payload on the day the path lands.

The converse is checked as an **absence of path literals** in `Fixture.swift` rather than by comparing the two
lists: `Fixture.endpoints` is written in terms of `Endpoint`'s own constants, so the compiler already refuses a
path that does not exist, and the way a guessed contract would actually get in is as a string.

**Ten payloads, one per shape the app decodes**: the budget in rupees and in dirhams, a drifted budget, the
`Money` exponent corpus, a token pair, `GET /v1/me` verified and unverified, the logout acknowledgement, and
the language preference in both languages. Every one is exercised by a decoding test, and the language one is
read the way the app reads it — through `APIClient.setLanguage` — because `LanguagePreference` is `private` to
`Networking` and a copy in the test target would be a second shape.

**The AED fixture carries `AED 8,000`, which is defect D1's own figure.** The rupee one stays the default
preview, so a screen that has gone back to hardcoding looks right against exactly one fixture in the corpus
and wrong against the standing one.

**The drift is a blank display string, not a missing key.** A missing key fails through `Decodable`'s
generated initialiser and would pass whatever `Money` decided; a blank one is refused by `Money`'s own guard,
which is the ADR-0003 rule that the client has no formatter to fall back on. The missing-key case is covered
too, by removing the key from the good fixture in the test rather than by keeping a third file. And the drift
is followed all the way to a screen: `HomeViewModel` over the drifted payload lands on `failed`, so the
failure demonstrably reaches the state a user sees rather than being caught by a decoder in a test only.

**One corpus means the test target stops writing payloads.** `TestBench` and `SessionCoordinatorTests` held
their own copies of the `GET /v1/me` and language shapes; both now read the files. Assertions about who is
signed in read `TestBench.identity` rather than repeating an email. **The exception is the access token**: a
canned JWT cannot carry a moving expiry, so `session-tokens.json` is dated 2100 for the shape and the session
suites keep minting tokens against a live clock. Said out loud in both places.

**`SnapshotPin` is the pin, as a value.** Device (`iPhone 17`) and runtime (26.5) — major and minor only,
since Apple's patch releases do not move SwiftUI's rendering and pinning the patch would make the suite skip
on every machine within a fortnight. The suite is `.enabled(if:)` on the pair matching the host, so a
developer elsewhere sees it **skip with the reason** rather than fail; CI (#10) pins the destination so it
actually runs. The device name comes from `SIMULATOR_DEVICE_NAME` rather than `UIDevice.current.name`, which
is main-actor isolated and cannot be read from a suite trait.

**`SnapshotCase` is the four, as a closed enum** — populated, empty, RTL, AX3 — with the count asserted. A
fifth is a decision, not a file. The empty case goes through `StateView` rather than a screen, and that is not
a shortcut: `LoadState.empty` comes from `isEmpty(_:)`, no screen that exists says so, and the screens with
genuine empty states are #18 and #21.

**The fixture JSON keeps shipping in the app bundle.** Issue #9 offers to move the corpus into the test
target if that becomes unacceptable; it has not. Ten files, 40 KB, no secrets, and `Fixtures/` *code* is
`#if DEBUG` so nothing reads them in a release build. Moving them would cost the previews their payloads — the
one thing ADR-0013's shared corpus exists to give them — and the alternative it names, inline payloads in
previews, is the second corpus this ADR spent its length removing.

## The blocked half, precisely

`swift-snapshot-testing` is **not** in the project, and it cannot be put there from here. Every class in the
package-reference family — `XCRemoteSwiftPackageReference`, `XCLocalSwiftPackageReference`,
`XCSwiftPackageProductDependency` — makes this Xcode refuse to open the project at all:

```
Exception: -[XCRemoteSwiftPackageReference _setOwner:]: unrecognized selector sent to instance
```

That happens with the object merely present in `objects`, referenced or not, at `objectVersion` 77, 78, 80,
and 90. So the format this Xcode writes for a package is not one that can be reproduced by hand, and adding
one is a GUI step: **File ▸ Add Package Dependencies… → `https://github.com/pointfreeco/swift-snapshot-testing`
→ Up to Next Major 1.19.4 → add `SnapshotTesting` to the `HisaabWiseTests` target only.**

What landed instead is the harness minus the comparison: the four cases, the pin, and a render of each case so
one that stops building fails now rather than on the day the baselines arrive.

The **app links no package products** is asserted in `Architecture/TestDependencyTests` and deliberately *not*
in the snapshot suite, which skips on every host but the pinned one — a guard rail that runs on one simulator
is not a guard rail. It is checked before the dependency exists on purpose: whoever performs the GUI step will
click a target picker, and this is what fails if they click the wrong one (ADR-0013: linked into the app it
would reach `PrivacyInfo.xcprivacy` and App Review).

## Consequences

- Coverage is now a property of the source rather than of anyone's memory, and it will fail *usefully* when
  ADR-0020's endpoints arrive: the first commit that adds `GET /v1/screens/home` to `Endpoint.swift` is told to
  bring a payload with it.
- **Three of the four snapshot cases cannot be photographed correctly without a hosted capture**, which is the
  second reason the library is required rather than preferred: a `BaseView` renders through a chrome that
  supplies `.task { load() }`, and `ImageRenderer` yields once before capturing — so its pixels are the
  spinner. This is now recorded in `SnapshotCase.drawsAFetchedScreen`.
- The snapshot suite skips on any host but the pinned one. That is the intended behaviour and it means the
  suite is **not** a gate on a developer's machine until #10 pins the destination.
- `TestBench.payload(_:)` traps on a missing fixture. Deliberate: a missing file is a bundle assembled wrong,
  not a test outcome, and returning empty `Data` would turn one broken resource into a dozen unrelated
  decoding failures somewhere else.
- The corpus is where the next screen ticket starts. Each of #17–#25 writes its payload here first, and its
  preview and its decoding test then read the same bytes.
