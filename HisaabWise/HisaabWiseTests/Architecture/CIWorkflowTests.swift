import Foundation
import Testing

/// The workflow, read as the checked-in file it is.
///
/// A pipeline is the one piece of this repo that cannot be verified by running it — the first real run
/// happens on a pull request into `release`, and by then a mistake is a red check on somebody's PR at the
/// worst moment. Everything about it that is a *decision* rather than a mechanism can be read out of the
/// YAML, so it is:
///
/// - **Rule 2's trigger set.** `release` and `main`, and nothing else. A `feature/mvp` trigger would make
///   local development wait on a macOS runner, which is the thing that rule exists to prevent.
/// - **The three pins.** Runner image, Xcode version, and simulator. Unpinned, a green suite becomes red
///   on an image rebuild — and worse for `SnapshotPin`, whose baselines are only meaningful on one pair.
/// - **That the destination still agrees with `SnapshotPin`.** These are two files that have to say the
///   same thing, and nothing else would notice them drifting apart.
/// - **Rule 3's absence of signing material.** Tests run unsigned on a simulator; a certificate, a
///   profile, or a keychain password appearing here is a credential in a public repository.
@Suite("The CI workflow")
struct CIWorkflowTests {
    private static let file = SourceTree.workflows.appending(path: "ios.yml")

    /// The workflow's **directives**, with its comments removed.
    ///
    /// For the same reason `SourceTree.codeLines` exists: this file explains its own pins in prose — "pinned,
    /// not `macos-latest`", "`feature/mvp` is deliberately pipeline-free" — and a scan that read those would
    /// fail on the very sentences that say the rule is being followed.
    private static func workflow() throws -> String {
        try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#") else { return "" }
                // A trailing comment, which in this file is always preceded by a space.
                return String(line).components(separatedBy: " #")[0]
            }
            .joined(separator: "\n")
    }

    /// Every `key: value` pair in the file, flattened. Enough to read a pin out of the `env:` block
    /// without a YAML parser — and a parser is not worth a dependency for four strings.
    private static func settings() throws -> [String: String] {
        var settings: [String: String] = [:]
        for line in try Self.workflow().split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
            settings[parts[0]] = parts[1]
        }
        return settings
    }

    @Test("the workflow is checked in, with the scripts it calls")
    func theWorkflowExists() throws {
        #expect(try !Self.workflow().isEmpty)

        for script in ["assert-build-settings.py", "test-summary.py"] {
            let path = SourceTree.ciScripts.appending(path: script)
            #expect(FileManager.default.fileExists(atPath: path.path()), "\(script) is missing")
        }
    }

    /// **The suite name in two languages.** `test-summary.py` fails the job when the snapshot suite did not
    /// run, and it finds that suite by its `@Suite` display name — a string in Python with nothing tying it to
    /// the string in Swift. It fails closed, so a rename is a false red rather than a false green, but a false
    /// red with a misleading message is still a morning lost.
    @Test("the summary script looks for a suite that exists")
    func theGateNamesARealSuite() throws {
        let script = try String(contentsOf: SourceTree.ciScripts.appending(path: "test-summary.py"), encoding: .utf8)
        let suite = try String(
            contentsOf: SourceTree.appSources
                .deletingLastPathComponent()
                .appending(path: "HisaabWiseTests/Snapshots/SnapshotSuiteTests.swift"),
            encoding: .utf8
        )

        #expect(script.contains(#"SNAPSHOT_SUITE = "The pinned snapshot harness""#))
        #expect(suite.contains(#"@Suite("The pinned snapshot harness""#))
    }

    /// The same, for the two suites the gate lets skip: an allow-list naming a suite that no longer exists
    /// would let a *different* skip through under its name.
    @Test("every allowed skip names a suite that exists")
    func theAllowListNamesRealSuites() throws {
        let script = try String(contentsOf: SourceTree.ciScripts.appending(path: "test-summary.py"), encoding: .utf8)
        let allowed = ["A real request against wrangler dev", "KeychainTokenStore against the real Keychain"]
        let testSources = SourceTree.appSources.deletingLastPathComponent().appending(path: "HisaabWiseTests")
        let walker = try #require(
            FileManager.default.enumerator(at: testSources, includingPropertiesForKeys: nil)
        )
        let sources = try walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined()

        for suite in allowed {
            #expect(script.contains(suite), "the allow-list no longer names \(suite)")
            #expect(sources.contains(#"@Suite("#) && sources.contains(suite), "no suite is called \(suite)")
        }
    }

    /// **The paths are asserted exactly, because they differ by one `../`.**
    ///
    /// Two steps run a script and they run from different places: the build-settings check needs
    /// `xcodebuild` in the directory holding the `.xcodeproj`, so it reaches back out of it, while the
    /// summary runs from the checkout root. Getting that wrong is a first-run failure that no local check
    /// would have caught — this is that check.
    @Test("each script is invoked at a path that resolves from its step's working directory")
    func theScriptPathsResolve() throws {
        let workflow = try Self.workflow()

        #expect(workflow.contains("python3 ../.github/scripts/assert-build-settings.py"))
        #expect(workflow.contains("python3 .github/scripts/test-summary.py"))
        // The one that reaches back is the one that sets a working directory, and it is the Xcode folder.
        #expect(workflow.contains("working-directory: HisaabWise"))
    }

    // MARK: - Rule 2

    @Test("it triggers on release and main, and on nothing else")
    func theTriggersAreTheTwoDeployedBranches() throws {
        let workflow = try Self.workflow()

        #expect(workflow.contains("branches: [release, main]"))
        // Twice: once for the pull request that gates the merge, once for the push that follows it.
        #expect(workflow.components(separatedBy: "branches: [release, main]").count == 3)
        #expect(
            !workflow.contains("feature/mvp"),
            "a feature/mvp trigger would put local development behind a macOS runner (Rule 2)"
        )
        // And no third way in. Each of these would run the pipeline on something other than the two
        // deployed branches, which is the whole of what Rule 2 restricts.
        for trigger in ["workflow_dispatch", "schedule:", "branches-ignore", "tags:", "workflow_call"] {
            #expect(!workflow.contains(trigger), "the workflow can also be triggered by \(trigger) (Rule 2)")
        }
    }

    // MARK: - The pins

    @Test("the runner image and the Xcode version are pinned")
    func theToolchainIsPinned() throws {
        let workflow = try Self.workflow()
        let settings = try Self.settings()

        #expect(settings["runs-on"] == "macos-26")
        #expect(
            !workflow.contains("macos-latest"),
            "an image that moves under the suite is a red build nobody caused"
        )
        #expect(settings["XCODE_VERSION"] == "26.6")
        // Selected, not merely named: the image ships several and its default changes when it is rebuilt.
        #expect(workflow.contains("xcode-select -s"))
    }

    /// **The two files that have to agree.** `SnapshotPin` decides which device and runtime the baselines
    /// belong to and skips the suite anywhere else; the workflow decides what CI runs on. Drift between
    /// them turns the snapshot cases into four tests that silently do not run — which is why the summary
    /// script fails the job on a skipped suite, and why this asserts they match in the first place.
    @Test("the workflow's destination is the pinned snapshot host")
    func theDestinationMatchesTheSnapshotPin() throws {
        let settings = try Self.settings()

        #expect(settings["SIMULATOR_NAME"] == SnapshotPin.device)
        #expect(settings["SIMULATOR_OS"] == "\(SnapshotPin.runtime.major).\(SnapshotPin.runtime.minor)")
        // And the destination is built from those two rather than written out again a third time.
        #expect(try Self.workflow().contains("name=$SIMULATOR_NAME,OS=$SIMULATOR_OS"))
    }

    @Test("the suite runs whole, with no test selection")
    func theWholeSuiteRuns() throws {
        let workflow = try Self.workflow()

        #expect(workflow.contains("xcodebuild test"))
        #expect(
            !workflow.contains("-only-testing"),
            "a filtered suite in CI is a gate with a hole in it"
        )
        #expect(!workflow.contains("-skip-testing"))
        // The result bundle, which is what turns a failure into named tests in the summary.
        #expect(workflow.contains("-resultBundlePath"))
    }

    // MARK: - Rule 3

    /// No signing material, and nothing that would need any. A simulator test needs no identity, so the
    /// presence of one of these words would mean either a credential in the repository or a job that will
    /// fail on a runner with an empty keychain.
    @Test("the workflow carries no signing material")
    func nothingIsSigned() throws {
        let workflow = try Self.workflow()

        for material in [
            "CODE_SIGN_IDENTITY", "PROVISIONING_PROFILE", "p12", "mobileprovision",
            "security import", "security create-keychain", "APP_STORE_CONNECT", "certificate",
        ] {
            #expect(!workflow.contains(material), "the workflow names \(material) (Rule 3)")
        }
        // And it says so positively, so a later job that *does* need signing cannot inherit this one's
        // silence by copying it.
        #expect(workflow.contains("CODE_SIGNING_ALLOWED=NO"))
    }

    /// The working tree, not only the workflow: a certificate sitting in the checkout is one `git add -A`
    /// away from being committed, and this suite is the thing that would have caught it.
    ///
    /// **The list is `.gitignore`'s**, read from the file rather than repeated — two lists for one rule is how
    /// `.p8` came to be ignored by one and unchecked by the other. `.git/` is skipped: what is in history is a
    /// different problem with a different remedy, and enumerating it on every run is slow for nothing.
    @Test("no credential file sits in the working tree")
    func theWorkingTreeHoldsNoCredentials() throws {
        let ignored = try String(
            contentsOf: SourceTree.repositoryRoot.appending(path: ".gitignore"),
            encoding: .utf8
        )
        let extensions = ["p12", "mobileprovision", "cer", "certSigningRequest", "p8", "pem", "key"]
        // Every extension this test knows about is one `.gitignore` also refuses, so the two cannot drift.
        for suffix in ["p12", "mobileprovision", "cer", "certSigningRequest", "p8"] {
            #expect(ignored.contains("*.\(suffix)"), ".gitignore no longer refuses *.\(suffix) (Rule 3)")
        }

        let walker = try #require(
            FileManager.default.enumerator(at: SourceTree.repositoryRoot, includingPropertiesForKeys: nil)
        )
        for case let url as URL in walker {
            if url.lastPathComponent == ".git" {
                walker.skipDescendants()
                continue
            }
            if extensions.contains(url.pathExtension) {
                Issue.record("\(url.lastPathComponent) is a credential and is in the working tree (Rule 3)")
            }
        }
    }
}
