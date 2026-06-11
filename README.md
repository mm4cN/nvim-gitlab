# nvim-gitlab

GitLab integration for Neovim.

Current focus is GitLab CI/CD workflows powered by `glab`.

## Features

- Validate `.gitlab-ci.yml`
- Show latest pipeline status
- List project pipelines
- Run pipelines
- Browse jobs from the latest pipeline
- Open job logs
- Health checks
- GitLab API integration

## Requirements

- Neovim 0.10+
- git
- glab
- GitLab Personal Access Token

## Configuration

Expose your token:

```bash
export GITLAB_TOKEN="your-token"
```

## Installation

### lazy.nvim

```lua
{
    "mm4cN/gitlab.nvim",
    config = function()
        require("gitlab").setup()
    end,
}
```

### Local development

```lua
{
    dir = "~/Projects/gitlab.nvim",
    name = "gitlab.nvim",
    lazy = false,
    config = function()
        require("gitlab").setup()
    end,
}
```

## Setup

```lua
require("gitlab").setup({
    glab_binary = "glab",
    default_branch = "main",
    ci_file = ".gitlab-ci.yml",
    picker = "vim_ui",
    scratch_height = 15,
    gitlab_token_env = "GITLAB_TOKEN",
})
```

## Commands

### Health

```vim
:checkhealth gitlab
:GitlabHealth
:GitlabAuth
```

### CI/CD

```vim
:GitlabCiValidate
:GitlabPipelineStatus
:GitlabPipelineList
:GitlabPipelineRun
:GitlabJobLogs
:GitlabJobLogs <job_id>
:GitlabJobRetry
```

## Examples

Validate CI configuration:

```vim
:GitlabCiValidate
```

Show latest pipeline status:

```vim
:GitlabPipelineStatus
```

Browse jobs from the latest pipeline and open logs:

```vim
:GitlabJobLogs
```

Open logs for a specific job:

```vim
:GitlabJobLogs 123456789
```

## Health Checks

Standard Neovim health check:

```vim
:checkhealth gitlab
```

Detailed plugin health information:

```vim
:GitlabHealth
```

## Roadmap

### v0.2.0

- Pipeline picker
- Open pipeline in browser
- Better status formatting

### v0.3.0

- Retry jobs
- Cancel jobs
- Cancel pipelines
- Download artifacts

### v0.4.0

- Statusline integration
- Pipeline cache

### v0.5.0

- Merge Requests
- MR checkout
- MR details

### v0.6.0

- Forge integration
- Pipeline failure analysis

## License

MIT
