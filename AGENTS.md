# nvim-gitlab

This is a Lua project designed to handle basic GitLab operations. It is a pure Lua wrapper around the GitLab API and the `glab` CLI tool.

# Commands

`make test` - Run the full test suite. Ensure all tests pass after implementing changes.

# Code Conventions

- Avoid narration. Do not add comments everywhere unless the code is not self documenting.
- Default to no comment.
- Comment only public facing API.
- Error handling: plugin MUST NOT crash, keep handling with `pcall` and default `vim` log behavior.
- Plain language. Avoid jargon.
- Explicit names. `pattern` not `pat`, `should_include` not `include_ok`, etc.

# General Rules

- Avoid over-exploring the codebase with excessive grep calls. Conduct a maximum of 3-4 searches, then pause and share findings.
- When asked to fix a test, fix the test itself, not the code being tested.

# Target Instructions

- Do only what has been asked. No more, no less.
- Create files only when required.
- Keep the codebase in a self-testable form.
- Each module should be independently testable.
- Do not over-engineer commentary; the maintainer knows the codebase.
