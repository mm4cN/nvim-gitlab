local auth = require("gitlab.auth")
local lint = require("gitlab.ci.lint")
local pipelines = require("gitlab.ci.pipelines")
local pipeline_runner = require("gitlab.ci.pipeline_runner")
local notification = require("gitlab.ui.notification")
local health = require("gitlab.ui.health")
local details = require("gitlab.ci.details")
local job_details = require("gitlab.ci.job_details")

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
  command("GitlabPipelineRun", pipeline_runner.open, {})
  command("GitlabPipelineStatus", pipelines.status, {})
  command("GitlabPipelineList", function()
    details.show()
  end, {})

  -- job helpers
  command("GitlabJobList", function()
    job_details.show()
  end, {})
end

return M
