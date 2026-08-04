local api = require("gitlab.api")
local actions = require("gitlab.ci.actions")
local artifacts = require("gitlab.ci.artifacts")
local buffer = require("gitlab.ui.buffer")
local format = require("gitlab.ci.format")
local git = require("gitlab.git")
local job_details = require("gitlab.ci.job_details")
local jobs_module = require("gitlab.ci.jobs")
local navigation = require("gitlab.ui.navigation")
local notification = require("gitlab.ui.notification")
local picker = require("gitlab.ui.picker")

local M = {}

local function repo_root()
  local root, err = git.root()

  if not root then
    notification.error(err)
    return nil
  end

  return root
end

local function show_pipeline(root, pipeline)
  local function build_view(pipeline_data, jobs_data)
    local lines = {
      "Pipeline #" .. tostring(pipeline_data.id),
      "",
      "Status: " .. format.status_icon(pipeline_data.status) .. " " .. tostring(pipeline_data.status),
      "Ref:     " .. tostring(pipeline_data.ref),
      "SHA:     " .. format.short_sha(pipeline_data.sha),
      "Created: " .. tostring(pipeline_data.created_at),
      "Updated: " .. tostring(pipeline_data.updated_at),
      "",
      "Jobs:",
      "",
    }

    if #jobs_data == 0 then
      table.insert(lines, "  No jobs found")
    else
      for _, job in ipairs(jobs_data) do
        table.insert(lines, format.job(job))
      end
    end

    local hints = {
      { key = "r",    label = "Refresh" },
      { key = "<CR>", label = "Details" },
      { key = "L",    label = "Logs" },
      { key = "A",    label = "Artifacts" },
      { key = "R",    label = "Re-run" },
      { key = "b",    label = "Back" },
      { key = "q",    label = "Quit" },
    }

    local function refresh_view()
      local refreshed_pipeline, pipeline_err = api.pipeline(pipeline.id, {
        cwd = root,
      })

      if not refreshed_pipeline then
        notification.error(pipeline_err)
        return
      end

      local refreshed_jobs, jobs_err = api.pipeline_jobs(pipeline.id, {
        cwd = root,
      })

      if not refreshed_jobs then
        notification.error(jobs_err)
        return
      end

      buffer.replace(build_view(refreshed_pipeline, refreshed_jobs))
    end

    return {
      title = "GitLab Pipeline #" .. tostring(pipeline_data.id),
      filetype = "gitlab",
      lines = lines,
      hints = hints,

      keymaps = {
        q = buffer.close_current,
        b = buffer.back,
        r = buffer.refresh,

        ["<CR>"] = function()
          local job_id = navigation.job_id_under_cursor()

          if not job_id then
            notification.error("No job id under cursor")
            return
          end

          job_details.show({
            job_id = job_id,
          })
        end,

        L = function()
          local job_id = navigation.job_id_under_cursor()

          if not job_id then
            notification.error("No job id under cursor")
            return
          end

          jobs_module.logs({
            args = job_id,
          })
        end,

        A = function()
          local job_id = navigation.job_id_under_cursor()
          if not job_id then
            notification.error("No job id under cursor")
            return
          end

          artifacts.download({
            job_id = job_id,
          })
        end,

        R = function()
          actions.rerun_pipeline(pipeline.id)
        end,
      },

      refresh = refresh_view,
    }
  end

  local pipeline_jobs, jobs_err = api.pipeline_jobs(pipeline.id, {
    cwd = root,
  })

  if not pipeline_jobs then
    notification.error(jobs_err)
    return
  end

  buffer.show(build_view(pipeline, pipeline_jobs))
end

local function pick_pipeline(root, callback)
  local pipelines, err = api.pipelines({
    cwd = root,
    per_page = 20,
  })

  if not pipelines then
    notification.error(err)
    return
  end

  if #pipelines == 0 then
    notification.error("No pipelines found")
    return
  end

  picker.select(pipelines, {
    prompt = "GitLab pipelines",
    select_label = "Details",
    format_item = format.pipeline,
    preview = function(pipeline)
      return {
        "Pipeline",
        string.rep("─", 12),
        "ID       " .. tostring(pipeline.id),
        "Ref      " .. format.value(pipeline.ref),
        "Status   " .. format.value(pipeline.status),
        "SHA      " .. format.short_sha(pipeline.sha),
        "Created  " .. format.datetime(pipeline.created_at),
        "Updated  " .. format.datetime(pipeline.updated_at),
      }
    end,
    actions = {
      {
        key = "<C-r>",
        label = "Re-run pipeline",
        callback = function(pipeline)
          actions.rerun_pipeline(pipeline.id)
        end,
      },
    },
  }, function(pipeline)
    if not pipeline then
      return
    end

    callback(pipeline)
  end)
end

function M.show(opts)
  opts = opts or {}

  local root = repo_root()

  if not root then
    return
  end

  if opts.pipeline_id and opts.pipeline_id ~= "" then
    local pipeline, err = api.pipeline(opts.pipeline_id, {
      cwd = root,
    })

    if not pipeline then
      notification.error(err)
      return
    end

    show_pipeline(root, pipeline)
    return
  end

  pick_pipeline(root, function(pipeline)
    show_pipeline(root, pipeline)
  end)
end

return M
