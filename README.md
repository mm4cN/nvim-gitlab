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
- glab
- [MunifTanjim/nui.nvim](https://github.com/MunifTanjim/nui.nvim) (required for `:GitlabPipelineRunProject`)

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
    default_branch = "main",
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

### Health Checks

- GitLab token validation
- glab availability checks
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
:GitlabPipelineRunProject   " cross-project runner with ref picker and pipeline variables
:GitlabPipelineList
:GitlabPipelineStatus
:GitlabPipelineDetails
:GitlabPipelineDetails <pipeline_id>
```

### Jobs

```vim
:GitlabJobList

:GitlabJobLogs
:GitlabJobLogs <job_id>

:GitlabJobRetry
:GitlabJobRetry <job_id>

:GitlabJobDetails
:GitlabJobDetails <job_id>

:GitlabJobArtifacts <job_id>
```

### Interactive Views

Refreshable pipeline and job views support:

- `r` Refresh current view
- `<CR>` Open details
- `L` Open logs
- `A` Download artifacts
- `R` Retry job / Re-run pipeline (auto-refreshes view)
- `P` Play manual job (auto-refreshes view)
- `]` Next page (pipeline list)
- `[` Previous page (pipeline list)
- `b` Navigate back
- `q` Close view


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

