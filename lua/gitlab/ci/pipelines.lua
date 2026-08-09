local actions = require("gitlab.ci.actions")
local api = require("gitlab.api")
local buffer = require("gitlab.ui.buffer")
local details = require("gitlab.ci.details")
local format = require("gitlab.ci.format")
local git = require("gitlab.git")
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

  local pipeline, err = api.run_pipeline({
    cwd = root,
    ref = branch,
  })

  if not pipeline then
    notification.error(err)
    return
  end

  local lines = {
    "Pipeline created",
    "",
    format.pipeline(pipeline),
  }

  buffer.show({
    title = "GitLab Pipeline Run",
    filetype = "gitlab",
    lines = lines,
  })
end

function M.list()
  local root = repo_root()
  if not root then
    return
  end

  local current_page = 1

  local function build_view(pipelines)
    local lines = {
      string.format("GitLab Pipelines - page %d", current_page),
      "",
    }

    if #pipelines == 0 then
      table.insert(lines, "No pipelines found")
    else
      for _, pipeline in ipairs(pipelines) do
        table.insert(lines, format.pipeline(pipeline))
      end
    end

    local hints = {
      { key = "r",    label = "Refresh" },
      { key = "<CR>", label = "Details" },
      { key = "R",    label = "Re-run" },
      { key = "]",    label = "Next page" },
      { key = "[",    label = "Previous page" },
      { key = "q",    label = "Quit" },
    }

    local function refresh_view()
      local refreshed_pipelines, err = api.pipelines({
        cwd = root,
        per_page = 20,
        page = current_page,
      })

      if not refreshed_pipelines then
        notification.error(err)
        return
      end

      buffer.replace(build_view(refreshed_pipelines))
    end

    local function next_page()
      local next_pipelines, err = api.pipelines({
        cwd = root,
        per_page = 20,
        page = current_page + 1,
      })

      if not next_pipelines then
        notification.error(err)
        return
      end

      if #next_pipelines == 0 then
        notification.info("No more pipelines")
        return
      end

      current_page = current_page + 1
      buffer.replace(build_view(next_pipelines))
    end

    local function previous_page()
      if current_page == 1 then
        notification.info("Already on first page")
        return
      end

      local prev_pipelines, err = api.pipelines({
        cwd = root,
        per_page = 20,
        page = current_page - 1,
      })

      if not prev_pipelines then
        notification.error(err)
        return
      end

      current_page = current_page - 1
      buffer.replace(build_view(prev_pipelines))
    end

    return {
      title = "GitLab Pipelines",
      filetype = "gitlab",
      lines = lines,
      hints = hints,

      keymaps = {
        q = buffer.close_current,
        r = buffer.refresh,
        ["]"] = next_page,
        ["["] = previous_page,

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

      refresh = refresh_view,
    }
  end

  local pipelines, err = api.pipelines({
    cwd = root,
    per_page = 20,
  })

  if not pipelines then
    notification.error(err)
    return
  end

  buffer.show(build_view(pipelines))
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
