---
description: "Review staged files for code quality (KISS, DRY, YAGNI, Clean Code) and fix linting issues. Use to clean up staged work before review or commit. Unlike code-review, this one edits the code: it applies refactors, runs the linter, and fills test gaps."
---

# Code Refinement

Review the staged files to ensure the changes adhere to the KISS, DRY, and YAGNI principles. Confirm that Clean Code standards are met (including clear, consistent naming and comments where needed).

Check for opportunities to use established framework utilities, composables, or library functions instead of hand-rolled logic. If the staged code reimplements behavior that the project's framework or core libraries already provide, flag it and suggest the existing alternative.

Verify that the project's UI framework components and utility classes are used where appropriate instead of custom CSS or HTML elements. Flag any custom styling that duplicates what the framework already provides.

Run the project's linting command and fix all reported errors and warnings. Discover the command from package scripts, a Makefile, CI config, or pre-commit config; if the project has no linter, note that and move on. Avoid using lint-suppression comments (e.g., eslint-disable, noqa, @ts-ignore) to make the lint pass unless absolutely necessary, and only with a clear justification in the code.

Review tests and code coverage: check whether existing tests adequately cover the new or modified code, add tests for any gaps you find, and update any existing tests that must change to handle the new behavior correctly. When finished, ensure everything is ready for a high-quality code review.

Do not stage, commit, or push. Leave every change in the working tree: the review loop stages what it needs on its own, and the commit is the developer's call.
