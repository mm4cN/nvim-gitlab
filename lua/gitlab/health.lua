local auth = require("gitlab.auth")
local config = require("gitlab.config")
local git = require("gitlab.git")
local glab = require("gitlab.glab")

local M = {}

local health = vim.health

local function ok(message)
  health.ok(message)
end

local function warn(message)
  health.warn(message)
end

local function error(message)
  health.error(message)
end

function M.check()
  health.start("gitlab.nvim")

  if vim.fn.executable("git") == 1 then
    ok("git found")
  else
    error("git not found")
  end

  if vim.fn.executable(config.options.glab_binary) == 1 then
    ok(config.options.glab_binary .. " found")
  else
    error(config.options.glab_binary .. " not found")
  end

  local token, token_err = auth.token()
  if token then
    ok(config.options.gitlab_token_env .. " configured")
  else
    warn(token_err)
  end

  local root, root_err = git.root()
  if root then
    ok("inside git repository: " .. root)
  else
    warn(root_err)
    return
  end

  local branch, branch_err = git.branch()
  if branch then
    ok("current branch: " .. branch)
  else
    warn(branch_err)
  end

  local remote, remote_err = git.remote_url()
  if remote then
    ok("origin remote: " .. remote)
  else
    warn(remote_err)
  end

  local user, user_err = glab.run_json({ "api", "user" }, {
    cwd = root,
  })

  if user then
    ok("GitLab API reachable as " .. (user.username or user.name or "unknown"))
  else
    error("GitLab API check failed: " .. user_err)
  end
end

return M
