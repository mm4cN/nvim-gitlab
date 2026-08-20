# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),  
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Include-aware discovery of legacy described CI/CD variables in the interactive pipeline runner.
- Reusable accessible-project picker for the pipeline runner and `:GitlabPipelineList`.
- Cross-project pipeline browsing with up to 100 recent pipelines available for local picker filtering.
- Fixed-height runner form viewport with rounded form/help panes, automatic focus scrolling, and a proportional scrollbar.
- Explicit public Lua API documentation for setup and statusline access.
- Actionable health diagnostics for required `glab` and `nui.nvim`, optional Telescope, and feature-specific token usage.

### Changed

- `:GitlabPipelineRun` is now the canonical interactive pipeline runner, with project/ref selection, CI discovery, and manual variables.
- Runner-wide `<C-p>`, `<C-r>`, and `<C-s>` mappings now select Project, select Ref, and run the pipeline from every focusable field. Enter remains field-local.
- Project changes use canonical GitLab project metadata, switch Ref to the selected project's default branch, and preserve manually added variables across discovery transitions.
- Cross-project pipeline details preserve the selected project through job lookup, logs, artifacts, retry/play, refresh, and pipeline rerun actions.
- YAML discovery now uses a compatible `yq` YAML-to-JSON transcoder instead of the previous limited local parser.
- Telescope selection falls back to `vim.ui` when Telescope is configured but unavailable.
- `:GitlabPipelineList` and `:GitlabJobList` now use the configured picker backend to select an item and open its details.
- The public command and configuration surfaces have been audited and stabilized for 1.0.

### Removed

- The redundant simple pipeline runner and its separate project-run command.
- The redundant `:GitlabPipelineDetails` and `:GitlabJobDetails` command names.
- The standalone `:GitlabJobLogs`, `:GitlabJobRetry`, and `:GitlabJobArtifacts` commands; these actions remain available from the pipeline details and job details views.
- The dedicated paginated pipeline-list buffer and its `[` / `]` navigation; pipeline selection now uses the configured picker backend.
- The unused `default_branch` configuration option.

### Fixed

- Unsupported YAML scalar constructs are ignored instead of being interpreted as literal input or variable values.
- Project and Ref picker cancellation, and selection of a project without a default branch, restore coherent runner values and focus.
- Pipeline List project selection remains available after choosing a project with no pipelines.

## [0.9.0] - 2026-08-18

### Added

- **Statusline API** — lightweight API for exposing current-branch pipeline status to statusline plugins. `require("gitlab.statusline").get()` returns a table with `status`, `icon`, `text`, and `pipeline_id` fields. Results are cached for 60 seconds per project+branch pair. Includes integration examples for native Neovim statusline and lualine.
- **Project CI/CD variables** — `:GitlabPipelineRunProject` now fetches and displays project-level CI/CD variables from GitLab. Only variables with a non-empty description are shown. Values are pre-filled from the API and can be edited before running. Project variables and user-defined pipeline variables are merged when triggering the pipeline; manual variables override matching project variable keys.

### Changed

- Project variables and pipeline variables (`:GitlabPipelineRunProject` runner) are now separate concepts. Project variables come from the GitLab API; pipeline variables are user-defined `KEY=VALUE` pairs. Both are passed to `glab ci run` as `--variables KEY:VALUE` arguments.

## [0.8.0] - 2026-08-16

### Added

- **Pipeline variables** — the cross-project runner now supports GitLab pipeline variables independently from `spec:inputs`. Press `a` in normal mode on any runner field to add a variable; enter it as `KEY=VALUE`. Variables are passed to `glab ci run` as `--variables KEY:VALUE`. Up to 7 variables can be added per run (UI limit, not a GitLab restriction).
- **Ref picker** — press `<C-r>` on the Ref field in the cross-project runner to pick a branch from the selected project. Branches are fetched from the GitLab API for the currently entered project. Manual ref entry remains available at all times.
- **Project context** — `project`, `ref`, and local repository root are now resolved together at runner startup. If any field cannot be resolved the runner opens with empty fields and reports the specific error. No partial context is used.

### Changed

- `:GitlabPipelineRunProject` initialises project, ref, and root as a unit via an explicit context. If context resolution fails the runner opens with empty fields rather than silently using partial git state.
- All project-scoped API functions (`pipelines`, `pipeline`, `pipeline_jobs`, `job`, `latest_pipeline`, `pipeline_inputs`, `run_pipeline`) now accept `opts.project`. When provided, the explicit project is always used and there is no fallback to the cwd-derived project on failure.

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
