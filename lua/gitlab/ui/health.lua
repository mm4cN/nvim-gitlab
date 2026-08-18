local auth = require("gitlab.auth")
local config = require("gitlab.config")
local git = require("gitlab.git")
local glab = require("gitlab.glab")
local buffer = require("gitlab.ui.buffer")

local M = {}

local function ok(label, value)
  if value and value ~= "" then
    return "✓ " .. label .. ": " .. value
  end

  return "✓ " .. label
end

local function fail(label, err)
  return "✗ " .. label .. ": " .. (err or "failed")
end

local function check_command(name)
  if vim.fn.executable(name) == 1 then
    return true, name
  end

  return false, name .. " not found"
end

function M.run()
  local lines = {
    "GitLab Health Check",
    "",
  }

  local git_ok, git_result = check_command("git")
  table.insert(lines, git_ok and ok("git", git_result) or fail("git", git_result))

  local glab_ok, glab_result = check_command(config.options.glab_binary)
  table.insert(lines, glab_ok and ok("glab", glab_result) or fail("glab", glab_result))
  if not glab_ok then
    table.insert(lines, "  Install glab and ensure it is available on PATH")
  end

  if pcall(require, "nui.input") then
    table.insert(lines, ok("nui.nvim", "required"))
  else
    table.insert(lines, fail("nui.nvim", "required dependency not found"))
    table.insert(lines, "  Install MunifTanjim/nui.nvim")
  end

  if config.options.picker == "telescope" then
    if pcall(require, "gitlab.ui.pickers.telescope") then
      table.insert(lines, ok("Telescope picker", "available"))
    else
      table.insert(lines, "! Telescope picker unavailable; using vim.ui fallback")
      table.insert(lines, "  Install nvim-telescope/telescope.nvim to use picker = \"telescope\"")
    end
  end

  local token, token_err = auth.token()
  table.insert(lines, token and ok("token", config.options.gitlab_token_env)
    or "• token: " .. token_err .. " (optional; only required by :GitlabAuth)")

  local root, root_err = git.root()
  table.insert(lines, root and ok("git root", root) or fail("git root", root_err))

  local branch, branch_err = git.branch()
  table.insert(lines, branch and ok("branch", branch) or fail("branch", branch_err))

  local remote, remote_err = git.remote_url()
  table.insert(lines, remote and ok("origin", remote) or fail("origin", remote_err))

  local host, host_err = git.remote_host()

  if host then
    if not auth.is_gitlab_host(host) then
      table.insert(lines, fail("GitLab host", "Remote host does not look like a GitLab host: " .. host))
    else
      table.insert(lines, ok("GitLab host", host))

      local _, auth_err = glab.auth_status(host, {
        cwd = root,
      })

      if auth_err then
        table.insert(lines, fail("glab auth", auth_err))
        table.insert(lines, "  Run: glab auth login --hostname " .. host)
      else
        table.insert(lines, ok("glab auth", host))
      end
    end
  else
    table.insert(lines, fail("GitLab host", host_err))
  end

  if root then
    local user, user_err = glab.run_json({ "api", "user" }, {
      cwd = root,
    })

    if user then
      table.insert(lines, ok("GitLab API", user.username or user.name or "reachable"))
    else
      table.insert(lines, fail("GitLab API", user_err))
    end
  else
    table.insert(lines, fail("GitLab API", "skipped, not inside git repo"))
  end

  buffer.show({
    title = "GitLab Health",
    filetype = "text",
    lines = lines,
  })
end

return M
