# nvim-gitlab

Interactive GitLab CI/CD workflows for Neovim powered by `glab`.

Browse pipelines, inspect jobs, view logs, download artifacts, and trigger CI actions directly from Neovim.

## Requirements

- Neovim 0.12+
- git
- glab

## Features

### CI Pipelines

- Run GitLab pipelines
- List project pipelines
- Show latest pipeline status
- Open pipeline details
- Re-run pipelines

### CI Jobs

- List jobs for the latest pipeline
- Open job details
- View job logs
- Retry jobs
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

## Setup

```lua
require("gitlab").setup({
    glab_binary = "glab",
    default_branch = "main",
    ci_file = ".gitlab-ci.yml",

    picker = "vim_ui",

    scratch_height = 15,

    gitlab_token_env = "GITLAB_TOKEN",

    artifacts_dir = "gitlab-artifacts",
    extract_artifacts = true,
})
```
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

:GitlabJobDetails <job_id>

:GitlabJobArtifacts <job_id>
```

### Interactive Views

Pipeline and job views support:

- `<CR>` Open details
- `L` Open logs
- `A` Download artifacts
- `R` Retry job / Re-run pipeline
- `b` Navigate back
- `q` Close view


## Planned Features

### CI/CD

- View refresh
- Artifact browser
- Better pipeline formatting

### Merge Requests

- MR list
- MR details
- MR checkout
- MR pipelines
