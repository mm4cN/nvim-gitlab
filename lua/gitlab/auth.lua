local config = require("gitlab.config")
local git = require("gitlab.git")
local glab = require("gitlab.glab")

local M = {}

function M.token()
  local env_name = config.options.gitlab_token_env
  local token = vim.env[env_name]

  if not token or token == "" then
    return nil, env_name .. " is not set"
  end

  return token, nil
end

function M.is_gitlab_host(host)
  if not host or host == "" then
    return false
  end

  if host == "gitlab.com" then
    return true
  end

  return host:find("gitlab", 1, true) ~= nil
end

function M.login()
  local root, root_err = git.root()
  if not root then
    return nil, root_err
  end

  local host, host_err = git.remote_host()
  if not host then
    return nil, host_err
  end

  if not M.is_gitlab_host(host) then
    return nil,
        "Remote host does not look like a GitLab host: " .. host .. "\n"
        .. "\n"
        .. "Current plugin authentication works only for GitLab remotes.\n"
        .. "If this repository is mirrored or uses a non-standard GitLab hostname,\n"
        .. "authenticate manually with:\n"
        .. "\n"
        .. "  glab auth login --hostname " .. host
  end

  local token, token_err = M.token()
  if not token then
    return nil, token_err
  end

  local _, login_err = glab.auth_login(host, token, {
    cwd = root,
  })

  if login_err then
    return nil,
        "Failed to authenticate glab for host "
        .. host
        .. ". This may not be a GitLab host, or the token may be invalid.\n"
        .. login_err
  end

  local _, status_err = glab.auth_status(host, {
    cwd = root,
  })

  if status_err then
    return nil, status_err
  end

  return host, nil
end

return M
