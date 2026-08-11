#!/usr/bin/env python3
"""Turn an `.xcresult` into a step summary, and fail the job on the two things a green log can hide.

Issue #10 asks that the run "fails the PR on any test failure, and surfaces the failing test names in the
summary". `xcodebuild` already fails the job on a failing test; what it does not do is tell you *which*
test from the check's front page, and a reviewer should not have to open a log to find out.

It also fails on **any skipped suite that is not on the allow-list**. A skip is silent — the log says
`TEST SUCCEEDED` while a suite ran nowhere — and the case that matters most is the snapshot one:
`SnapshotPin` skips it when the device or runtime is not the pinned pair (ADR-0027), which is precisely the
pins having drifted apart. Two suites are allowed to skip, because their conditions are environmental
rather than accidental: the live-Worker suite needs `wrangler dev`, and the Keychain suite needs a writable
Keychain. Anything else skipping is coverage that left without a decision.

**The gate is fail-closed.** A suite counts as having run only if a test case in it *passed*; an
unrecognised or missing result is treated as not having run. For the one check whose whole purpose is
refusing a silent pass, an unknown value must not be a pass.
"""

import json
import os
import subprocess
import sys

# The suite that must have run, by its `@Suite` display name. `CIWorkflowTests` asserts this literal still
# appears in `SnapshotSuiteTests.swift`, since a rename here and there are two edits nothing else ties
# together.
SNAPSHOT_SUITE = "The pinned snapshot harness"

# The suites whose skip is a fact about the machine rather than a loss of coverage.
ALLOWED_SKIPS = [
    "A real request against wrangler dev",
    "KeychainTokenStore against the real Keychain",
]


def xcresult(subcommand: str, path: str) -> dict:
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", subcommand, "--path", path, "--compact"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return json.loads(output)


def walk(node: dict, path: str = "") -> list[tuple[str, str, str]]:
    """Every node in the test tree as (nodeType, name, result), depth first."""
    name = node.get("name", "?")
    found = [(node.get("nodeType", "?"), f"{path}/{name}".lstrip("/"), node.get("result", "?"))]
    for child in node.get("children") or []:
        found += walk(child, f"{path}/{name}")
    return found


def write_summary(lines: list[str]) -> None:
    print("\n".join(lines))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as file:
            file.write("\n".join(lines) + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: test-summary.py <path to .xcresult>", file=sys.stderr)
        return 2
    path = sys.argv[1]

    summary = xcresult("summary", path)
    nodes = [node for root in xcresult("tests", path).get("testNodes") or [] for node in walk(root)]

    total = summary.get("totalTestCount", 0)
    passed = summary.get("passedTests", 0)
    failed = summary.get("failedTests", 0)
    skipped = summary.get("skippedTests", 0)

    lines = [
        "## iOS test suite",
        "",
        f"**{summary.get('result', 'unknown')}** — {passed} passed, {failed} failed, {skipped} skipped "
        f"of {total}.",
    ]

    failures = summary.get("testFailures") or []
    if failures:
        lines += ["", "### Failing tests", ""]
        for failure in failures:
            name = failure.get("testName") or failure.get("targetName") or "unnamed test"
            message = (failure.get("failureText") or "").strip().splitlines()
            first = message[0] if message else "no message"
            lines.append(f"- **{name}** — {first}")

    skipped_suites = [name.split("/")[-1] for kind, name, result in nodes
                      if kind == "Test Suite" and result == "Skipped"]
    unexpected = [name for name in skipped_suites if name not in ALLOWED_SKIPS]
    if skipped_suites:
        lines += ["", "### Skipped suites", ""]
        lines += [f"- {name}{'' if name in ALLOWED_SKIPS else ' — **not on the allow-list**'}"
                  for name in skipped_suites]

    # Fail-closed: the suite ran only if a test case in it passed. `any(result != "Skipped")` would let an
    # unrecognised result through, and this is the check that must not be generous.
    snapshot_cases = [result for kind, name, result in nodes
                      if kind == "Test Case" and SNAPSHOT_SUITE in name]
    snapshot_ran = bool(snapshot_cases) and any(result == "Passed" for result in snapshot_cases)

    if not snapshot_ran:
        lines += [
            "",
            f"> **The {SNAPSHOT_SUITE!r} suite did not run.** `SnapshotPin` skips it off its pinned "
            "device and runtime, so either the workflow's destination and the pin have drifted apart, or "
            "the suite is no longer in the target (ADR-0027, ADR-0028).",
        ]
    if unexpected:
        lines += [
            "",
            f"> **{len(unexpected)} suite(s) skipped without being allowed to**: "
            f"{', '.join(unexpected)}. A skip is silent, so a new one is a decision somebody has to make "
            "on purpose — add it to `ALLOWED_SKIPS` with a reason, or fix the condition.",
        ]

    write_summary(lines)

    if failed or failures or not snapshot_ran or unexpected:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
