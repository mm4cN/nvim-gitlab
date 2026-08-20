# nvim-gitlab

<p align="center">
  <img src="assets/icon.png" width="256" alt="nvim-gitlab">
</p>

<p align="center">
    Interactive GitLab CI/CD workflows for Neovim powered by `glab` and GitLab APIs.
</p>

Browse pipelines, inspect jobs, view logs, download artifacts, and trigger CI actions directly from Neovim.

## Focus

nvim-gitlab is intentionally focused on GitLab CI/CD workflows.

Current features include:

- Pipeline browsing
- Pipeline details
- Job browsing
- Job details
- Job logs
- Job retry
- Pipeline re-run
- Artifact downloads

Merge Requests, Issues, and project management features are currently out of scope.

## Requirements

- Neovim 0.12+
- git
- [glab](https://gitlab.com/gitlab-org/cli) (required)
- yq with YAML-to-JSON single- and multi-document support (required for CI discovery)
- [MunifTanjim/nui.nvim](https://github.com/MunifTanjim/nui.nvim) (required)
- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional; used when `picker = "telescope"`)

`GITLAB_TOKEN` is optional when `glab` is already authenticated. It is required
only when using `:GitlabAuth`. CI discovery probes the installed `yq` for its
generic YAML-to-JSON single- and multi-document transcoding capabilities.

## Installation

### lazy.nvim

```lua
{
    "mm4cN/nvim-gitlab",
    dependencies = { "MunifTanjim/nui.nvim" },
    config = function()
        require("gitlab").setup()
    end,
}
```

### packer.nvim

```lua
use({
    "mm4cN/nvim-gitlab",
    requires = { "MunifTanjim/nui.nvim" },
    config = function()
        require("gitlab").setup()
    end,
})
```

### mini.deps

```lua
MiniDeps.add({
    source = "mm4cN/nvim-gitlab",
    depends = { "MunifTanjim/nui.nvim" },
})

require("gitlab").setup()
```

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({
    { src = "https://github.com/MunifTanjim/nui.nvim" },
    { src = "https://github.com/mm4cN/nvim-gitlab" },
})

require("gitlab").setup()
```

## Setup

```lua
require("gitlab").setup({
    glab_binary = "glab",
    ci_file = ".gitlab-ci.yml",

    picker = "vim_ui",      -- default picker backend

    scratch_height = 15,    -- scratch buffer height

    gitlab_token_env = "GITLAB_TOKEN",

    artifacts_dir = "gitlab-artifacts",
    extract_artifacts = true,

    notification = {
        -- Optional; defaults to vim.notify.
        handler = function(message, level, opts)
            vim.notify(message, level, opts)
        end,
    },
})
```

The notification handler is backend-agnostic, so it can delegate to Noice,
Snacks, nvim-notify, or another implementation without adding a plugin
dependency to nvim-gitlab.

### Telescope Support

To enable Telescope integration:

```lua
require("gitlab").setup({
    picker = "telescope",
})
```

If Telescope is not installed, gitlab.nvim automatically falls back to vim.ui.select().

With Telescope enabled, pickers provide additional features:
- Preview pane showing available actions and selected item details
- Custom keybindings for quick actions (e.g., `<C-r>` to re-run a pipeline directly from the picker)

## Features

### Pickers

- Picker backend abstraction
- Telescope picker backend
- vim.ui fallback picker backend

### CI Pipelines

- Run GitLab pipelines
- List project pipelines
- Show latest pipeline status
- Open pipeline details
- Re-run pipelines
- Cross-project pipeline runner with project/ref pickers, CI inputs, and pipeline variables
- Browse and operate on pipelines from any accessible project

### CI Jobs

- List jobs for the latest pipeline
- Open job details
- View job logs
- Retry jobs
- Play manual jobs
- Download job artifacts

### Interactive Navigation

- Pipeline → Job drilldown
- Reusable scratch window
- View history navigation (`b`)
- Context-aware actions

### Statusline API

- Lightweight API for exposing pipeline status to statuslines
- Current-branch pipeline status with caching
- Native statusline and lualine integration examples

### Health Checks

- Required and optional dependency diagnostics
- glab authentication and GitLab API validation
- CI configuration validation

## Commands

### Health

```vim
:checkhealth gitlab
:GitlabHealth
:GitlabAuth
```

### CI Validation

```vim
:GitlabCiValidate
```

### Pipelines

```vim
:GitlabPipelineRun
:GitlabPipelineStatus
:GitlabPipelineList
```

### Jobs

```vim
:GitlabJobList
```

The pipeline runner uses a compatible `yq` only to transcode YAML documents to
JSON. Lua discovers `spec:inputs` from the root `.gitlab-ci.yml` and legacy
described variables from GitLab's include-expanded merged CI YAML. Discovery
reports single- and multi-document capability failures separately. Successful
strategy probing is cached for the current Neovim session.

Pipeline fields with configured options use selection menus (`j`/`k` or arrow
keys). Tab and Shift-Tab continue across editable and selection fields. Option
labels are normalized for display, while selected values are submitted without
destructive sanitization.

The runner uses a fixed-height, scrollable form beside a non-focusable
keybinding legend. Tab and Shift-Tab move between fields and automatically
scroll the destination into view. The scrollbar indicates the current position
when the form contains more fields than fit in the viewport.

Runner-wide actions are available from Project, Ref, input, variable, and option
fields:

- `<C-p>` select a project
- `<C-r>` select a ref for the current project
- `<C-s>` run the pipeline
- `a` add a variable and `d` remove a user-added variable (normal mode)
- `q` or `<Esc>` close the runner

Enter remains field-local: it commits Project/Ref edits and retains the native
interaction of the focused field; it is not the Run shortcut. Selecting another
project resolves its canonical GitLab path, switches Ref to its default branch,
and refreshes CI discovery while preserving manually added variables.

In `:GitlabPipelineList`, press `<C-p>` to select another accessible project.
The active project is shown in the picker prompt, and pipeline/job details,
logs, artifacts, refreshes, and reruns retain that selected project context.

### Interactive Views

Refreshable pipeline and job views support:

- `r` Refresh current view
- `<CR>` Open details
- `L` Open logs
- `A` Download artifacts
- `R` Retry job / Re-run pipeline (auto-refreshes view)
- `P` Play manual job (auto-refreshes view)
- `b` Navigate back
- `q` Close view

## Public Lua API

The supported Lua API is:

- `require("gitlab").setup(opts)` — configure and initialize the plugin.
- `require("gitlab.statusline").get()` — return cached statusline data without blocking.
- `require("gitlab.statusline").clear_cache()` — clear statusline context and pipeline caches.

Other `gitlab.*` modules are internal implementation details and may change.

## Statusline Integration

The plugin provides a lightweight API for displaying current-branch pipeline status in your statusline.

### Usage

```lua
require("gitlab.statusline").get()
```

Returns a table with pipeline status information:

- `status` — Raw pipeline status string (success, failed, running, pending, etc.)
- `icon` — Single Unicode character representing the status
- `text` — Ready-to-use Nerd Font string, such as `: ✓ success`
- `pipeline_id` — Numeric pipeline ID
- `watch_count` — Number of active pipeline watches, omitted when zero
- `watch_text` — Formatted watch indicator, such as `Watching: 2`, omitted when zero

When watches are active, `text` appends ` | Watching: N`. The leading GitLab
glyph requires a Nerd Font. The watch indicator
is available even when the current-branch pipeline status is unavailable.
Otherwise, an empty table `{}` is returned when no pipeline is found or on
error.

### Native Statusline Example

```lua
vim.o.statusline = "%{%v:lua.require('gitlab.statusline').get().text or ''%}"
```

### Lualine Example

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      function()
        return require("gitlab.statusline").get().text or ""
      end,
    },
  },
})
```

Results are cached for 60 seconds per project+branch pair.

## Development

### Running Tests

```bash
make test
```

Tests run headlessly via Neovim and require no GitLab credentials or network access.

## Planned Features

### CI/CD

- Artifact browser
- Pipeline filtering
- Pipeline search
