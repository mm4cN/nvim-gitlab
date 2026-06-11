local auth = require("gitlab.auth")
local lint = require("gitlab.ci.lint")
local pipelines = require("gitlab.ci.pipelines")
local jobs = require("gitlab.ci.jobs")
local notification = require("gitlab.ui.notification")
local health = require("gitlab.ui.health")
local details = require("gitlab.ci.details")
local job_details = require("gitlab.ci.job_details")

local M = {}

local function gitlab_auth()
  local ok, err = auth.check()

  if not ok then
    notification.error(err)
    return
  end

  notification.info("GitLab token detected")
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
    nargs = 1,
  })
end

return M
