# Code Refinement

Improve the quality of the staged changes, then fix what you find. This is not
a bug hunt: correctness review is `code-review`'s job.

## Phase 1: review against four angles

Run `git diff --staged` to get the changes under review. That diff is the
scope for every angle below.

If you have a subagent tool (Claude Code's Agent tool, or your CLI's
equivalent), launch one agent per angle, all in a single message so they run
concurrently, and give each the staged diff plus its angle. Tell each agent it
is read-only: it reports findings, it does not edit. If you have no subagent
tool, work through all four angles yourself in one pass. Do not skip an angle
for lack of fan-out.

Each finding needs a file, a line, a one-line summary, and the concrete cost:
what is duplicated, wasted, or harder to maintain.

### Simplification

Confirm the changes adhere to KISS, DRY, and YAGNI, and that Clean Code
standards are met (clear, consistent naming and comments where needed). Flag
unnecessary complexity the diff adds: redundant or derivable state, copy-paste
with slight variation, deep nesting, dead code left behind. Name the simpler
form that does the same job.

### Reuse

Check for opportunities to use established framework utilities, composables,
or library functions instead of hand-rolled logic. If the staged code
reimplements behavior that the project's framework or core libraries already
provide, flag it and name the existing alternative to call instead. This covers
the UI framework too: flag custom CSS or hand-built HTML that duplicates a
component or utility class the framework already ships. Grep shared/utility
modules and files adjacent to the change.

### Efficiency

Flag wasted work the diff introduces: redundant computation or repeated I/O,
independent operations run sequentially, blocking work added to startup or hot
paths, and long-lived objects built from closures or captured environments,
which keep the whole enclosing scope alive for the object's lifetime. Name the
cheaper alternative.

### Altitude

Check that each change fixes the root cause at the right depth rather than
patching a symptom with a fragile bandaid. Special cases layered on shared
infrastructure are a sign the fix isn't deep enough: prefer the simpler, more
general change to the underlying mechanism over adding special cases, and name
that change.

## Phase 2: apply the fixes

Dedup findings that point at the same line or mechanism, then fix each
remaining one directly. Skip any finding whose fix would change intended
behavior, require changes well outside the staged diff, or that you judge to
be a false positive; note the skip rather than arguing with it.

## Phase 3: lint and tests

Run the project's linting command and fix all reported errors and warnings.
Discover the command from package scripts, a Makefile, CI config, or
pre-commit config; if the project has no linter, note that and move on. Avoid
using lint-suppression comments (e.g. eslint-disable, noqa, @ts-ignore) to make
the lint pass unless absolutely necessary, and only with a clear justification
in the code.

Review tests and code coverage: check whether existing tests adequately cover
the new or modified code, add tests for any gaps you find, and update any
existing tests that must change to handle the new behavior correctly. When
finished, ensure everything is ready for a high-quality code review.

Finish with a brief summary of what was fixed and what was skipped, or confirm
the code was already clean. If you reviewed without the fan-out, say so, so
whoever reads the summary isn't misled about what actually ran.

Do not stage, commit, or push. Leave every change in the working tree: the
review loop stages what it needs on its own, and the commit is the developer's
call.
