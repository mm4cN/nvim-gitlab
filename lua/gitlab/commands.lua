local auth = require("gitlab.auth")
local lint = require("gitlab.ci.lint")
local pipelines = require("gitlab.ci.pipelines")
local jobs = require("gitlab.ci.jobs")
local notification = require("gitlab.ui.notification")
local health = require("gitlab.ui.health")

local M = {}

local function gitlab_auth()
  local ok, err = auth.check()

  if not ok then
    notification.error(err)
    return
  end

  notification.info("GitLab token detected")
end

function M.setup()
  vim.api.nvim_create_user_command("GitlabAuth", gitlab_auth, {})
  vim.api.nvim_create_user_command("GitlabHealth", health.run, {})

  vim.api.nvim_create_user_command("GitlabCiValidate", lint.validate, {})

  vim.api.nvim_create_user_command("GitlabPipelineRun", pipelines.run, {})
  vim.api.nvim_create_user_command("GitlabPipelineList", pipelines.list, {})
  vim.api.nvim_create_user_command("GitlabPipelineStatus", pipelines.status, {})

  vim.api.nvim_create_user_command("GitlabJobRetry", jobs.retry, {
    nargs = "?",
  })
  vim.api.nvim_create_user_command("GitlabJobLogs", jobs.logs, {
    nargs = "?",
  })
end

return M
