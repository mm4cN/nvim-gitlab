local actions = require("gitlab.ci.actions")
local buffer = require("gitlab.ui.buffer")
local details = require("gitlab.ci.details")
local git = require("gitlab.git")
local glab = require("gitlab.glab")
local navigation = require("gitlab.ui.navigation")
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
    filetype = "gitlab",
    lines = vim.split(output, "\n", { plain = true }),

    keymaps = {
      q = buffer.close_current,

      ["<CR>"] = function()
        local pipeline_id = navigation.pipeline_id_under_cursor()

        if not pipeline_id then
          notification.error("No pipeline id under cursor")
          return
        end

        details.show({
          pipeline_id = pipeline_id,
        })
      end,

      R = function()
        local pipeline_id = navigation.pipeline_id_under_cursor()
        if not pipeline_id then
          notification.error("No pipeline id under cursor")
          return
        end
        actions.rerun_pipeline(pipeline_id)
      end,
    },
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
