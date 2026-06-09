local config = require("gitlab.config")

local M = {}

function M.token()
  local env_name = config.options.gitlab_token_env
  local token = vim.env[env_name]

  if not token or token == "" then
    return nil, env_name .. " is not set"
  end

  return token, nil
end

function M.check()
  local _, err = M.token()

  if err then
    return false, err
  end

  return true, nil
end

return M
