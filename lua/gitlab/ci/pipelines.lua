local git = require("gitlab.git")
local glab = require("gitlab.glab")
local buffer = require("gitlab.ui.buffer")
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

function M.run()
  local root = repo_root()
  if not root then
    return
  end

  local branch = current_branch()
  if not branch then
    return
  end

  local output, err = glab.run({
    "pipeline",
    "run",
    "-b",
    branch,
  }, {
    cwd = root,
  })

  if err then
    notification.error(err)
    return
  end

  buffer.show({
    title = "GitLab Pipeline Run",
    filetype = "text",
    lines = vim.split(output, "\n", { plain = true }),
  })
end

function M.list()
  local root = repo_root()
  if not root then
    return
  end

  local output, err = glab.run({
    "pipeline",
    "list",
    "--per-page",
    "20",
  }, {
    cwd = root,
  })

  if err then
    notification.error(err)
    return
  end

  buffer.show({
    title = "GitLab Pipelines",
    filetype = "text",
    lines = vim.split(output, "\n", { plain = true }),
  })
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

  local output, err = glab.run({
    "pipeline",
    "list",
    "--ref",
    branch,
    "--per-page",
    "1",
  }, {
    cwd = root,
  })

  if err then
    notification.error(err)
    return
  end

  buffer.show({
    title = "GitLab Pipeline Status",
    filetype = "text",
    lines = vim.split(output, "\n", { plain = true }),
  })
end

return M
