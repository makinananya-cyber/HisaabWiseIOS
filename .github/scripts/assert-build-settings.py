#!/usr/bin/env python3
"""Assert the build settings the platform baseline depends on, as the build actually resolves them.

Issue #10 asks for these to be *asserted in CI, not just set* — "a template regression should fail a
check, since it already happened once". `BuildConfigurationTests` checks what `project.pbxproj` says,
which is the written value; this checks what `xcodebuild` resolves, which is the value that ships. The two
can differ: an `.xcconfig`, an inherited setting, or a command-line override sits between them.

Four settings, each with a decision behind it:

    IPHONEOS_DEPLOYMENT_TARGET  18.0                            ADR-0001
    SWIFT_VERSION               6.0 — the Swift 6 language mode  ADR-0001
    TARGETED_DEVICE_FAMILY      1 — iPhone only                  ADR-0001
    …UISupportedInterfaceOrientations_iPhone  portrait only      ADR-0001

**All three configurations, not the scheme's default.** `-showBuildSettings` with no `-configuration`
resolves Debug, which is the one configuration that never ships — and `Staging.xcconfig` and
`Release.xcconfig` are exactly where an override would sit (ADR-0010).

Python rather than shell because `-showBuildSettings -json` is JSON, and `grep` over it would pass on a
setting that appeared in a comment or in another target's dictionary.
"""

import argparse
import json
import subprocess
import sys

# ADR-0010's three configurations. Named here rather than discovered, so a fourth one that nobody wired
# into CI fails the `xcodebuild` call loudly instead of being skipped quietly.
CONFIGURATIONS = ["Debug", "Staging", "Release"]

EXPECTED = {
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "SWIFT_VERSION": "6.0",
    "TARGETED_DEVICE_FAMILY": "1",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
}


def resolved_settings(scheme: str, destination: str, configuration: str) -> dict[str, str]:
    """The app target's settings, as `xcodebuild` resolves them for one configuration."""
    output = subprocess.run(
        [
            "xcodebuild",
            "-showBuildSettings",
            "-scheme",
            scheme,
            "-configuration",
            configuration,
            "-destination",
            destination,
            "-json",
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    # `xcodebuild` prefixes the JSON with progress lines on a cold checkout, so the document is found
    # rather than assumed to start at byte zero.
    start = output.index("[")
    targets = json.loads(output[start:])

    for entry in targets:
        if entry.get("target") == scheme:
            return entry["buildSettings"]
    raise SystemExit(f"xcodebuild reported no settings for the {scheme} target: {[t.get('target') for t in targets]}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scheme", required=True)
    parser.add_argument("--destination", required=True)
    arguments = parser.parse_args()

    failures = []
    for configuration in CONFIGURATIONS:
        print(f"{configuration}:")
        settings = resolved_settings(arguments.scheme, arguments.destination, configuration)

        for key, expected in EXPECTED.items():
            actual = settings.get(key)
            if actual != expected:
                failures.append(f"  {configuration}: {key}: expected {expected!r}, resolved {actual!r}")
            else:
                print(f"  {key} = {actual}")

    if failures:
        print("\nThe platform baseline has moved (ADR-0001):", file=sys.stderr)
        print("\n".join(failures), file=sys.stderr)
        return 1

    print("\nThe platform baseline resolves as ADR-0001 decided it, in all three configurations.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
