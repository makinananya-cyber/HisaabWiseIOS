# ADR-0028 — CI pins three things, asserts what it builds, and refuses a silent skip

**Status:** accepted
**Extends:** [ADR-0013](0013-testing-and-previews.md) (which decided *that* `xcodebuild test` runs on the
`release` PR and that the simulator is pinned in CI — not what pins it or what a pass has to mean),
[ADR-0027](0027-corpus-coverage-and-the-pinned-harness.md) (the pin as a value)
**Changes a document outside this repo:** `DEVELOPMENT_PLAN.md` §1 — see the last section

## Context

`feature/mvp` has no pipeline by design, so until now nothing has run this suite except a person. Issue #10
asks for the suite on the `release` PR, and the asking is the easy part. Four things about a first pipeline
are decisions rather than mechanics.

**What "pinned" has to cover.** A macOS runner image decides which Xcode versions exist and which simulator
runtimes are installed. `macos-latest` moves when GitHub rebuilds the image, and for a suite whose snapshot
baselines are only meaningful on one device-and-runtime pair (ADR-0027) that is a red build nobody caused.

**What a pass has to mean.** `SnapshotPin` makes the snapshot suite **skip** when the host is not the pinned
pair. That is right for a developer's machine and wrong for CI: the log says `TEST SUCCEEDED`, the four cases
ran nowhere, and nothing says so. A green check that quietly covers less than it did is worse than a red one.

**Where the build settings are asserted.** Issue #10 asks for iOS 18.0, the Swift 6 language mode,
iPhone-only, and portrait-only to be "asserted in CI, not just set — a template regression should fail a
check, since it already happened once".

**How a failure reads.** `xcodebuild` fails the job on a failing test and says which one somewhere in a few
thousand lines of log. A reviewer looking at a red check should not have to open it.

## Decision

**Three pins, and they are named once.** `runs-on: macos-26` (GA, arm64), `XCODE_VERSION: 26.6` selected
explicitly with `xcode-select` — the image ships seven Xcodes and its *default* changes when it is rebuilt —
and the destination built from `SIMULATOR_NAME` and `SIMULATOR_OS`. `CIWorkflowTests` asserts the last two
equal `SnapshotPin`'s device and runtime: two files have to say the same thing, and nothing else would
notice them drifting apart.

**The summary script fails the job on a skip that nobody decided on.** It reads the `.xcresult`, writes
totals, failing test names, and skipped suites to the step summary, and exits non-zero if a test failed, if
the snapshot suite did not run, or if any suite skipped that is not on an explicit allow-list. Two suites are
on it, because their conditions are facts about the machine rather than lost coverage: the live-Worker suite
needs `wrangler dev`, and the Keychain suite needs a writable Keychain. `CIWorkflowTests` asserts that all
three of those names still name real suites.

**The gate is fail-closed.** A suite counts as having run only if a case in it *passed* — not merely if its
result was something other than `Skipped`, which would let an unrecognised or missing value through. For the
one check whose entire purpose is refusing a silent pass, an unknown result must not be a pass.

**The build settings are asserted three ways, because each catches something the others cannot.**
`BuildConfigurationTests` reads `project.pbxproj` — what the project *says*, at every place it says it. The
workflow runs `xcodebuild -showBuildSettings -json` **for each of the three configurations** and checks what
the build *resolves*: with no `-configuration` it would resolve Debug, which is the one configuration that
never ships, and `Staging.xcconfig` and `Release.xcconfig` are exactly where an override would sit. And a
plist check closes the hole the other two leave: `INFOPLIST_KEY_*` settings only reach the built app if the
`Info.plist` does not already carry the key, so an explicit `UISupportedInterfaceOrientations` would ship
landscape with every other check green. JSON is parsed rather than `grep`ped, because a `grep` over build
settings passes on a value that appeared in a comment or in another target's dictionary.

**No signing material, and it is said positively.** Tests run on a simulator, which needs no identity, and
the workflow passes `CODE_SIGNING_ALLOWED=NO` so a runner with an empty keychain can never be asked for one.
`CIWorkflowTests` scans the workflow for the words a signing job would use, and the whole repository for the
file extensions a credential arrives as (Rule 3).

**Triggers are `release` and `main`, on both `pull_request` and `push`, and a scan forbids `feature/mvp`**
(Rule 2). Least privilege — `permissions: contents: read` — and `concurrency` cancels a superseded run,
because macOS runner minutes are this project's scarcest CI resource.

**The workflow is tested, since it cannot be run.** Its first real execution is on somebody's pull request
into `release`, and a mistake found then is found at the worst moment. So everything about it that is a
decision is read out of the YAML by `CIWorkflowTests`: the triggers, the three pins, the agreement with
`SnapshotPin`, that no test selection narrows the run, that the two script paths resolve from their steps'
*working directories* — they differ by one `../`, and getting that wrong is the exact class of first-run
failure this suite exists to prevent — and the absence of signing material. The scan strips YAML comments
first, for the reason `SourceTree.codeLines` exists: this workflow explains its own pins in prose, and a scan
that read those sentences would fail on the very words that say the rule is being followed.

**Action versions are tagged, not SHA-pinned, and that is an exemption rather than an oversight.**
`actions/checkout@v4` and `actions/upload-artifact@v4` float within their major version. The argument
against `macos-latest` does not transfer: an action moves what the job *does around* the build, not the
toolchain that compiles it or the runtime that renders the pixels, so a patch to `checkout` cannot turn a
green suite red for reasons nobody caused. SHA-pinning them is the supply-chain-hardening posture and is
worth revisiting if this workflow ever handles a secret; today it handles none.

## Consequences

- **The pipeline has never run.** Everything asserted here was verified locally: both scripts were run
  against real `.xcresult` bundles — green, with a failing test, with the snapshot suite skipped, and with it
  absent — and the YAML was parsed. What cannot be verified from here is the runner itself: that
  `/Applications/Xcode_26.6.app` is the path on `macos-26`, and that its iOS 26.5 runtime carries an
  `iPhone 17`. Both come from the image manifest rather than from a run, and the first PR into `release` is
  what confirms them.
- **A runtime the image no longer ships is now a red build rather than a silent skip**, which is the intended
  trade. If GitHub drops iOS 26.5, the summary step fails with the reason and the fix is a decision — move
  the pin and re-record the baselines — rather than a mystery.
- The four snapshot cases still have no baselines, because the library is a GUI step away (ADR-0027). The
  skip gate is what makes that visible: when the package lands, the suite compares pictures; until then it
  renders each case and the gate proves it ran.
- `-resolvePackageDependencies` is a no-op today and is in the workflow anyway, so that the day the snapshot
  library arrives a resolution failure is its own red step with its own message.
- Two Python scripts in `.github/scripts/` are the first non-Swift, non-TypeScript code in this workspace.
  Justified narrowly: both parse JSON, both are the wrong shape in shell, and `python3` is on the runner and
  on every developer's Mac. A third one is a smell.

## The document outside this repo

`DEVELOPMENT_PLAN.md` lives in the **workspace root, which is not a git repository**, so this change is not
in this commit. Its §1 said "Xcode project | Does not exist. **Hard blocker on all iOS work** — GUI-only
bootstrap". That row now records what exists, and names the GUI-only step that genuinely remains: adding a
Swift package. A dated note under the table marks the two repository rows as superseded and points at
`CONTEXT.md` and `docs/adr/` for the current state, rather than rewriting a section whose value is being the
record of where the plan started.
