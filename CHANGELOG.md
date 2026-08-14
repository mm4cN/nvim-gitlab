# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),  
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.7.0] - 2026-08-14

### Added

- **Pipeline pagination** — `]` / `[` navigate next and previous pages in the pipeline list view.
- **Automatic refresh after mutations** — retry job, play manual job, retry pipeline jobs, and rerun pipeline now automatically refresh the current view on success.
- **Loading notifications** — all mutating CI operations (job retry, job play, pipeline rerun, pipeline run) show a loading notification before the blocking call.
- **Cross-project pipeline runner** (`:GitlabPipelineRunProject`) — interactive `nui.nvim`-based form for running a pipeline against any accessible GitLab project. Pre-fills project and branch from the current repository. Supports Tab / S-Tab navigation between fields and `r` to refresh.
- **`spec:inputs` discovery** (experimental) — fetches the root `.gitlab-ci.yml` via the Repository Files API and parses the `spec:inputs` block locally. Discovered inputs are rendered as editable fields in the runner. Only simple 2-space indented YAML with scalar defaults and block-style options lists is supported; `include:` directives, anchors, array defaults, and complex YAML are not.
- **Typed pipeline input formatting** — inputs passed to `glab ci run --input` use the correct typed syntax: `int`, `float` (inferred from value), `bool` (validated as `true`/`false`), `array` (comma-separated values only).
- `git.remote_project()` — extracts `namespace/project` (including nested subgroups) from the git origin remote URL.
- `glab.run_pipeline()` — cross-project pipeline execution via `glab ci run --repo --input`.
- `nui.nvim` declared as a required dependency.

### Changed

- `api.run_pipeline()` remains REST-based and returns pipeline JSON (used by `:GitlabPipelineRun`); not used by the cross-project runner.

### Fixed

- Refreshable views introduced in 0.6 now also cover the job list view correctly after pipeline operations.

