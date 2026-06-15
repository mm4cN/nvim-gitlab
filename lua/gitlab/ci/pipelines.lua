local actions = require("gitlab.ci.actions")
local api = require("gitlab.api")
local buffer = require("gitlab.ui.buffer")
local details = require("gitlab.ci.details")
local format = require("gitlab.ci.format")
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

  local pipelines, err = api.pipelines({
    cwd = root,
    per_page = 20,
  })

  if not pipelines then
    notification.error(err)
    return
  end

  local hints = {
    { key = "<CR>", label = "Details" },
    { key = "R",    label = "Re-run" },
    { key = "q",    label = "Quit" },
  }

  local lines = {
    "GitLab Pipelines",
    "",
  }

  if #pipelines == 0 then
    table.insert(lines, "No pipelines found")
  else
    for _, pipeline in ipairs(pipelines) do
      table.insert(lines, format.pipeline(pipeline))
    end
  end

  buffer.show({
    title = "GitLab Pipelines",
    filetype = "gitlab",
    lines = lines,
    hints = hints,

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

  buffer.show({
    title = "GitLab Pipeline Status",
    filetype = "gitlab",
    lines = lines,
  })
end

return M
