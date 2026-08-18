local api = require("gitlab.api")
local buffer = require("gitlab.ui.buffer")
local format = require("gitlab.ci.format")
local git = require("gitlab.git")
local notification = require("gitlab.ui.notification")

local M = {}

local function repo_root()
  local root, err = git.root()
  if not root then
    notification.error(err)
    return nil
  end

  return root
end

local function current_branch()
  local branch, err = git.branch()
  if not branch then
    notification.error(err)
    return nil
  end

  return branch
end

function M.status()
  local root = repo_root()
  if not root then
    return
  end

  local branch = current_branch()
  if not branch then
    return
  end

  local pipelines, err = api.pipelines({
    cwd = root,
    ref = branch,
    per_page = 1,
  })

  if not pipelines then
    notification.error(err)
    return
  end

  local lines = {
    "GitLab Pipeline Status",
    "",
  }

  if #pipelines == 0 then
    table.insert(lines, "No pipeline found for branch: " .. branch)
  else
    table.insert(lines, format.pipeline(pipelines[1]))
  end

  local hints = {
    { key = "q", label = "Quit" },
  }

  buffer.show({
    title = "GitLab Pipeline Status",
    filetype = "gitlab",
    lines = lines,
    hints = hints,
    keymaps = {
      q = buffer.close_current,
    },
  })
end

return M
