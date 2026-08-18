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
- [MunifTanjim/nui.nvim](https://github.com/MunifTanjim/nui.nvim) (required)
- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional; used when `picker = "telescope"`)

`GITLAB_TOKEN` is optional when `glab` is already authenticated. It is required
only when using `:GitlabAuth`. `yq` is not required.

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
})
```

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
- Cross-project pipeline runner with ref picker and pipeline variables

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

The pipeline runner discovers `spec:inputs` from the root `.gitlab-ci.yml` and
legacy described variables from GitLab's merged CI YAML. Discovery intentionally
supports a limited YAML subset: 2-space indentation, plain or simply quoted
scalar values, and block-style `options` lists. Anchors and aliases, multiline
scalars, inline collections, tabs, and escaped quoted scalars are not decoded.
Unsupported scalar values are ignored rather than interpreted. This keeps YAML
discovery dependency-free; `yq` is not required.

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
- `text` — Ready-to-use formatted string: `icon .. " " .. status`
- `pipeline_id` — Numeric pipeline ID

Returns an empty table `{}` when no pipeline is found or on error.

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
