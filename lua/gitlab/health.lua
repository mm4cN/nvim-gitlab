local auth = require("gitlab.auth")
local config = require("gitlab.config")
local git = require("gitlab.git")
local glab = require("gitlab.glab")
local yq = require("gitlab.ci.yq")

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
    health.info("Install glab and ensure it is available on PATH")
  end

  if pcall(require, "nui.input") then
    ok("nui.nvim found (required)")
  else
    error("nui.nvim not found (required)")
    health.info("Install MunifTanjim/nui.nvim")
  end

  local yq_ok, yq_err = yq.check({ force = true })
  if yq_ok then
    ok("yq YAML-to-JSON capabilities found (required for CI discovery)")
  else
    error(yq_err)
    health.info("Install a compatible yq YAML-to-JSON transcoder and ensure it is on PATH")
  end

  if config.options.picker == "telescope" then
    if pcall(require, "gitlab.ui.pickers.telescope") then
      ok("Telescope picker available")
    else
      warn("Telescope picker unavailable; using vim.ui fallback")
      health.info("Install nvim-telescope/telescope.nvim to use picker = \"telescope\"")
    end
  end

  local token, token_err = auth.token()
  if token then
    ok(config.options.gitlab_token_env .. " configured")
  else
    health.info(token_err .. " (optional; only required by :GitlabAuth)")
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

  local host, host_err = git.remote_host()

  if host then
    if not auth.is_gitlab_host(host) then
      warn("Remote host does not look like a GitLab host: " .. host)
    else
      ok("GitLab host: " .. host)

      local _, auth_err = glab.auth_status(host, {
        cwd = root,
      })

      if auth_err then
        error("glab is not authenticated for " .. host)
        health.info("Run: glab auth login --hostname " .. host)
      else
        ok("glab authenticated for " .. host)
      end
    end
  else
    warn(host_err)
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
