---
description: "Audit package dependency updates for supply-chain risk: publish-age gate, changelog/diff verification, security advisories, community signals, and breaking changes. Use whenever a branch, PR, or working directory changes a dependency manifest or lockfile (package.json, requirements.txt, pyproject.toml, Gemfile, go.mod, Cargo.toml, pom.xml, build.gradle, composer.json, pubspec.yaml, or the lockfile beside them), including Dependabot/Renovate batches and newly added packages."
---

# Package Update Supply Chain Review

## Review Workflow

For each updated or newly added package, work through all five checks below. Prefer CLI and API lookups (`npm view`, `pip index`, `gh api`, `curl` against registry/OSV endpoints) over web browsing. Never invent a result for a check you could not actually perform: report it as **SKIPPED** with the reason. Present findings in a single summary report at the end, grouped by package, and flag any failing check as a **HOLD** to investigate before merging.

### 1. Publication Age Gate

Confirm the release is at least 7 days old. Compromised and typosquatted releases are usually caught within the first few days, so letting one bake gives scanners and the community time to notice.

1. Look up the publish date for the exact version (`npm view <pkg> time --json`, `curl https://pypi.org/pypi/<pkg>/<version>/json`, or the registry's page).
2. Under 7 days → **HOLD - TOO NEW**, with the publish date, the age in days, and a recommendation to wait or pin to the prior version.

### 2. Changelog and Diff Verification

Confirm the code changes match what the release notes claim.

1. Locate the changelog or releases page for the new version (`gh release view <tag> --repo <org>/<repo>`).
2. Identify the claimed changes.
3. Skim the source diff between the old and new version (`gh api repos/<org>/<repo>/compare/v1.2.3...v1.4.0`).
4. Look for discrepancies: unexpected new files, new network calls, obfuscated code, post-install scripts that were not there before.
5. Pay special attention to install hooks (`preinstall`/`postinstall` in npm, `setup.py` entry points in Python, `build.rs` in Rust); they execute automatically and are a top supply chain vector.

**Red flags to call out:**

- Minified or obfuscated source added to an otherwise readable codebase
- New outbound HTTP/DNS calls, especially to IP addresses or unusual domains
- Environment variable reads for tokens, keys, or credentials
- New native/binary dependencies or compiled assets
- CI config or build script changes that fetch remote resources

### 3. Security Advisory Review

1. Query advisories for the package name and version range: `gh api /advisories --method GET -f "affects=<pkg>"`, the OSV API (`curl -s https://api.osv.dev/v1/query -d '{"package":{"name":"<pkg>","ecosystem":"<ecosystem>"}}'`), or ecosystem tools (`npm audit`, `pip-audit`, `cargo audit`).
2. If the update is itself a security patch, note the CVE(s) it addresses and confirm the fix is present in the version being adopted.
3. Check whether the new version introduces new advisories, since a patch can pull in a vulnerable transitive dependency.
4. Report as **No known advisories**, **Fixes CVE-XXXX-YYYY (severity)**, or **HOLD - OPEN ADVISORY: CVE-XXXX-YYYY**.

### 4. Community Signals (best effort)

Look for real users reporting problems, compromises, or regressions with this release.

1. Check the repo's issues filed after the release date (`gh api "search/issues?q=repo:<org>/<repo>+created:><release-date>"`).
2. With web access, also search the package name + version on Stack Overflow, Hacker News, and the ecosystem's channels, looking for several people reporting the same crash or suspicious activity. Without web access, limit this check to the CLI/API sources and say so.
3. Compare download counts against the package's historical trend where the registry exposes them; a sudden spike or drop can indicate typosquatting or an abandoned fork.

Report a brief sentiment summary, "No community issues found for this version" if clean, or **SKIPPED** with the reason.

### 5. Breaking Changes and Migration Notes

1. Check the bump against semver. Breaking changes in a minor or patch release are a red flag on their own, either accidental or a sign of poor maintenance.
2. Read the migration guide or upgrade notes if one exists.
3. Look in the diff for removed or renamed exports, changed function signatures, altered default values, removed configuration options, or dropped runtime/platform support.
4. Search the codebase for usages of anything changed or removed. List the files and line numbers that may need updates.
5. Note changes to peer dependency requirements, minimum runtime versions (Node, Python, Ruby), or required environment variables.

Report as **No breaking changes**; **Breaking changes detected** with what changed and which files are affected; or **Potential breaking changes** for behavioral shifts that compile and import fine but alter runtime behavior (e.g. a default timeout dropping from 30s to 5s).

## Output Format

Present the full review as a structured report:

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

- **New dependencies** (not just version bumps): same five checks, plus verify it is the intended package (compare against similarly named popular ones for typosquatting) and review maintenance health: last commit date, maintainer count, bus factor.
- **Lockfile-only changes** with no manifest change: still review the transitive packages that changed, though a lighter touch is acceptable for patch-level bumps in well-known packages.
- **Monorepo groups** (`@babel/*`, `@angular/*`): treat as one coordinated release, which reduces but does not eliminate individual diff review.
- **Private/internal packages:** the publication age gate may not apply; diff verification and breaking change checks still do. Never send internal package names or versions to public registry or advisory endpoints. Query the private registry where it exposes an API, otherwise mark those checks **SKIPPED** with the reason.

## Priorities

Start with the publication age gate; it is the fastest check and immediately flags the riskiest updates. In large batches (Dependabot/Renovate), prioritize direct dependencies over transitive ones, and packages with install hooks over those without. For high-download packages from well-known orgs, the changelog and community checks can be lighter; never skip the security advisory check.
