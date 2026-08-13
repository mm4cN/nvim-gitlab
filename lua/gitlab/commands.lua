local auth = require("gitlab.auth")
local lint = require("gitlab.ci.lint")
local pipelines = require("gitlab.ci.pipelines")
local pipeline_runner = require("gitlab.ci.pipeline_runner")
local jobs = require("gitlab.ci.jobs")
local notification = require("gitlab.ui.notification")
local health = require("gitlab.ui.health")
local details = require("gitlab.ci.details")
local job_details = require("gitlab.ci.job_details")
local artifacts = require("gitlab.ci.artifacts")

local M = {}

local function gitlab_auth()
  local host, err = auth.login()

  if not host then
    notification.error(err)
    return
  end

  notification.info("glab authenticated for " .. host)
end

local function command(name, callback, opts)
  vim.api.nvim_create_user_command(name, callback, opts or {})
end

function M.setup()
  command("GitlabAuth", gitlab_auth, {})
  command("GitlabHealth", health.run, {})
  command("GitlabCiValidate", lint.validate, {})

  -- pipeline helpers
  command("GitlabPipelineRun", pipelines.run, {})
  command("GitlabPipelineRunProject", pipeline_runner.open, {})
  command("GitlabPipelineList", pipelines.list, {})
  command("GitlabPipelineStatus", pipelines.status, {})
  command("GitlabPipelineDetails", function(opts)
    details.show({
      pipeline_id = opts.args,
    })
  end, {
    nargs = "?",
  })

  -- job helpers
  command("GitlabJobList", jobs.list)
  command("GitlabJobRetry", jobs.retry, {
    nargs = "?",
  })
  command("GitlabJobLogs", jobs.logs, {
    nargs = "?",
  })
  command("GitlabJobDetails", function(opts)
    job_details.show({
      job_id = opts.args,
    })
  end, {
    nargs = "?",
  })
  command("GitlabJobArtifacts", function(opts)
    artifacts.download({
      job_id = opts.args,
    })
  end, {
    nargs = 1,
  })
end

return M
