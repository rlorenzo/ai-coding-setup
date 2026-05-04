# Package Update Supply Chain Review

Review dependency updates to catch supply chain attacks, breaking changes, and risky packages before they land in your codebase.

## When to Use This Skill

Activate this review whenever a branch, PR, or working directory includes changes to dependency manifests or lockfiles. Common triggers include version bumps in package.json, requirements.txt, pyproject.toml, Gemfile, go.mod, Cargo.toml, pom.xml, build.gradle, composer.json, pubspec.yaml, or their corresponding lockfiles.

## Review Workflow

For each updated or newly added package, work through all five checks below. Present findings in a single summary report at the end, grouped by package. Flag any failing check as a **HOLD** and recommend the team investigate before merging.

---

### 1. Publication Age Gate

**Goal:** Confirm the release is at least 7 days old to allow the community time to discover and report compromises.

**Steps:**

1. Look up the package on its registry (npm, PyPI, RubyGems, crates.io, pub.dev, Maven Central, Go module proxy, Packagist, NuGet, etc.).
2. Find the publish date for the exact version being pulled in.
3. Calculate the number of days between the publish date and today.
4. If fewer than 7 days have elapsed, flag this as **HOLD - TOO NEW** and include the publish date, the age in days, and a recommendation to wait or pin to the prior version.

**Why this matters:** Attackers who hijack a maintainer account or publish a typosquatted package are often caught within the first few days. Letting a release "bake" gives the community, automated scanners, and the maintainer time to notice anomalies.

---

### 2. Changelog and Diff Verification

**Goal:** Confirm the code changes match what the release notes claim.

**Steps:**

1. Locate the changelog, release notes, or GitHub releases page for the new version.
2. Identify the claimed changes (bug fixes, features, refactors, etc.).
3. Skim the actual source diff between the old and new version (use the repo's compare view, e.g. `github.com/<org>/<repo>/compare/v1.2.3...v1.4.0`).
4. Look for discrepancies: Are there unexpected new files? New network calls? Obfuscated code? Post-install scripts that were not present before?
5. Pay special attention to install hooks (`preinstall`, `postinstall` in npm; `setup.py` entry points in Python; `build.rs` changes in Rust; etc.) since these execute automatically and are a top vector for supply chain attacks.

**Red flags to call out:**

- Minified or obfuscated source added to an otherwise readable codebase
- New outbound HTTP/DNS calls, especially to IP addresses or unusual domains
- Environment variable reads for tokens, keys, or credentials
- New native/binary dependencies or compiled assets
- Changes to CI config or build scripts that fetch remote resources

---

### 3. Security Advisory Review

**Goal:** Check whether the package or specific version has known vulnerabilities.

**Steps:**

1. Search the GitHub Advisory Database (GHSA), the National Vulnerability Database (NVD), and the ecosystem-specific advisory source (npm audit, pip-audit/Safety DB, RustSec, etc.) for the package name and version range.
2. Check whether the update itself is a security patch. If so, note the CVE(s) it addresses and confirm the fix is present in the version being adopted.
3. Check whether the new version introduces any new advisories. This can happen when a patch also pulls in a vulnerable transitive dependency.
4. Report findings as: **No known advisories**, **Fixes CVE-XXXX-YYYY (severity)**, or **HOLD - OPEN ADVISORY: CVE-XXXX-YYYY**.

---

### 4. Community Signals

**Goal:** See if real users are reporting problems, compromises, or regressions with this release.

**Steps:**

1. Check the package's GitHub Issues (filter to issues opened after the release date).
2. Search the repository's Discussions tab if available.
3. Search for the package name + version on relevant forums: Stack Overflow, Reddit (r/programming, r/node, r/python, r/rust, etc.), Hacker News, and the ecosystem's community channels (e.g. Discord servers for popular frameworks).
4. Look for patterns: multiple people reporting the same crash, unexpected behavior, or suspicious activity.
5. Note download counts and whether they are consistent with the package's historical trends. A sudden spike or drop can indicate typosquatting or an abandoned fork.

**Report as:** A brief summary of community sentiment, or "No community issues found for this version" if clean.

---

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

---

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

| Check                  | Status       | Details                          |
|------------------------|--------------|----------------------------------|
| Publication age        | PASS / HOLD  | Published <date>, <N> days ago   |
| Changelog verification | PASS / WARN  | <brief note>                     |
| Security advisories    | PASS / HOLD  | <CVEs or "None found">           |
| Community signals      | PASS / WARN  | <brief note>                     |
| Breaking changes       | PASS / WARN  | <brief note or "None">           |

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
