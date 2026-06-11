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

  local token, token_err = auth.token()
  table.insert(lines, token and ok("token", config.options.gitlab_token_env) or fail("token", token_err))

  local root, root_err = git.root()
  table.insert(lines, root and ok("git root", root) or fail("git root", root_err))

  local branch, branch_err = git.branch()
  table.insert(lines, branch and ok("branch", branch) or fail("branch", branch_err))

  local remote, remote_err = git.remote_url()
  table.insert(lines, remote and ok("origin", remote) or fail("origin", remote_err))

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
