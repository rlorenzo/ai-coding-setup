---
description: "Audit package dependency updates for supply-chain risk: publish-age gate, changelog/diff verification, security advisories, community signals, and breaking changes."
---

# Package Update Supply Chain Review

Review dependency updates to catch supply chain attacks, breaking changes, and risky packages before they land in your codebase.

## When to Use This Skill

Activate this review whenever a branch, PR, or working directory includes changes to dependency manifests or lockfiles. Common triggers include version bumps in package.json, requirements.txt, pyproject.toml, Gemfile, go.mod, Cargo.toml, pom.xml, build.gradle, composer.json, pubspec.yaml, or their corresponding lockfiles.

## Review Workflow

For each updated or newly added package, work through all five checks below. Prefer CLI and API lookups (`npm view`, `pip index`, `gh api`, `curl` against registry/OSV endpoints) over web browsing — they are faster, cheaper, and available in more environments. Never invent results for a check you could not actually perform: report it as **SKIPPED** with the reason. Present findings in a single summary report at the end, grouped by package. Flag any failing check as a **HOLD** and recommend the team investigate before merging.

### 1. Publication Age Gate

**Goal:** Confirm the release is at least 7 days old. Compromised or typosquatted releases are usually caught within the first few days, so letting a release "bake" gives the community and automated scanners time to notice.

**Steps:**

1. Look up the publish date for the exact version on its registry — e.g. `npm view <pkg> time --json`, `curl https://pypi.org/pypi/<pkg>/<version>/json`, `gem info <pkg> --remote`, or the registry's web page.
2. Calculate the number of days between the publish date and today.
3. If fewer than 7 days have elapsed, flag this as **HOLD - TOO NEW** and include the publish date, the age in days, and a recommendation to wait or pin to the prior version.

### 2. Changelog and Diff Verification

**Goal:** Confirm the code changes match what the release notes claim.

**Steps:**

1. Locate the changelog, release notes, or GitHub releases page for the new version (e.g. `gh release view <tag> --repo <org>/<repo>`).
2. Identify the claimed changes (bug fixes, features, refactors, etc.).
3. Skim the actual source diff between the old and new version (e.g. `gh api repos/<org>/<repo>/compare/v1.2.3...v1.4.0` or the repo's compare view).
4. Look for discrepancies: Are there unexpected new files? New network calls? Obfuscated code? Post-install scripts that were not present before?
5. Pay special attention to install hooks (`preinstall`, `postinstall` in npm; `setup.py` entry points in Python; `build.rs` changes in Rust; etc.) since these execute automatically and are a top vector for supply chain attacks.

**Red flags to call out:**

- Minified or obfuscated source added to an otherwise readable codebase
- New outbound HTTP/DNS calls, especially to IP addresses or unusual domains
- Environment variable reads for tokens, keys, or credentials
- New native/binary dependencies or compiled assets
- Changes to CI config or build scripts that fetch remote resources

### 3. Security Advisory Review

**Goal:** Check whether the package or specific version has known vulnerabilities.

**Steps:**

1. Query advisory sources for the package name and version range: `gh api /advisories --method GET -f "affects=<pkg>"`, the OSV API (`curl -s https://api.osv.dev/v1/query -d '{"package":{"name":"<pkg>","ecosystem":"<ecosystem>"}}'`), or ecosystem tools (`npm audit`, `pip-audit`, `cargo audit`).
2. Check whether the update itself is a security patch. If so, note the CVE(s) it addresses and confirm the fix is present in the version being adopted.
3. Check whether the new version introduces any new advisories. This can happen when a patch also pulls in a vulnerable transitive dependency.
4. Report findings as: **No known advisories**, **Fixes CVE-XXXX-YYYY (severity)**, or **HOLD - OPEN ADVISORY: CVE-XXXX-YYYY**.

### 4. Community Signals (best effort)

**Goal:** See if real users are reporting problems, compromises, or regressions with this release.

**Steps:**

1. Check the package's GitHub Issues for reports filed after the release date (e.g. `gh api "search/issues?q=repo:<org>/<repo>+created:><release-date>"` or `gh issue list --repo <org>/<repo>`).
2. If you have web access, also search for the package name + version on Stack Overflow, Hacker News, and the ecosystem's community channels; look for patterns such as multiple people reporting the same crash or suspicious activity.
3. Compare download counts against the package's historical trend where the registry exposes them (e.g. `npm view <pkg>` plus the npm downloads API). A sudden spike or drop can indicate typosquatting or an abandoned fork.
4. Without web access, limit this check to what the CLI/API sources above can answer and say so.

**Report as:** A brief summary of community sentiment, "No community issues found for this version" if clean, or **SKIPPED** with the reason if the sources were unreachable.

### 5. Breaking Changes and Migration Notes

**Goal:** Identify API or behavioral changes that could break existing code.

**Steps:**

1. Check if the version bump follows semver. A major version bump signals intentional breaking changes. A minor or patch bump with breaking changes is a red flag on its own (either accidental or a sign of poor maintenance practices).
2. Read the migration guide or upgrade notes if one exists.
3. Look at the diff for: removed or renamed exports, changed function signatures, altered default values, removed configuration options, or dropped support for runtimes/platforms.
4. Search the codebase for usages of any changed or removed APIs. List the files and line numbers that may need updates.
5. Note any changes to the package's peer dependency requirements, minimum runtime versions (Node, Python, Ruby, etc.), or required environment variables.

**Report as:**

- **No breaking changes** for seamless upgrades.
- **Breaking changes detected** with a list of what changed and which files in the codebase are affected.
- **Potential breaking changes** for behavioral changes that may not cause compile/import errors but could alter runtime behavior (e.g., a default timeout changing from 30s to 5s).

## Output Format

Present the full review as a structured report. Here is the template:

```text
# Package Update Review

## Summary
- Packages reviewed: N
- Holds: N (list package names)
- Clean: N

## Per-Package Review

### <package-name>: <old-version> -> <new-version>

| Check                  | Status              | Details                          |
|------------------------|---------------------|----------------------------------|
| Publication age        | PASS / HOLD         | Published <date>, <N> days ago   |
| Changelog verification | PASS / WARN         | <brief note>                     |
| Security advisories    | PASS / HOLD         | <CVEs or "None found">           |
| Community signals      | PASS / WARN / SKIPPED | <brief note>                   |
| Breaking changes       | PASS / WARN         | <brief note or "None">           |

**Recommendation:** APPROVE / HOLD / APPROVE WITH NOTES

<details if any check is WARN or HOLD>

(Repeat for each package)
```

## Edge Cases

- **New dependencies** (not just version bumps): Apply the same five checks but also verify the package is the intended one (check for typosquatting by comparing to similarly named popular packages) and review its overall maintenance health (last commit date, number of maintainers, bus factor).
- **Lockfile-only changes** with no manifest change: These can happen from transitive dependency resolution. Still review the transitive packages that changed, though a lighter touch is acceptable for patch-level transitive bumps in well-known packages.
- **Monorepos with many packages:** Group related packages (e.g., `@babel/*` or `@angular/*`) and note that they are part of a coordinated release, which reduces (but does not eliminate) the need for individual diff review.
- **Private/internal packages:** The publication age gate may not apply, but the diff verification and breaking change checks still do.

## Tips for Efficiency

- Start with the publication age gate; it is the fastest check and can immediately flag the riskiest updates.
- For large dependency updates (e.g., Dependabot batches), prioritize direct dependencies over transitive ones, and prioritize packages with install hooks.
- If a package has hundreds of thousands of weekly downloads and is maintained by a well-known org (e.g., Meta, Google, Vercel), the changelog and community checks can be lighter. But never skip the security advisory check.
