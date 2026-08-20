local api = require("gitlab.api")
local actions = require("gitlab.ci.actions")
local artifacts = require("gitlab.ci.artifacts")
local format = require("gitlab.ci.format")
local git = require("gitlab.git")
local job_details = require("gitlab.ci.job_details")
local jobs_module = require("gitlab.ci.jobs")
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
  local pipeline_jobs, jobs_err = api.pipeline_jobs(pipeline.id, { cwd = root })

  if not pipeline_jobs then
    notification.error(jobs_err)
    return
  end

  local do_show_pipeline -- forward declaration

  do_show_pipeline = function(pipeline_data, jobs_data)
    picker.show_pipeline({
      pipeline = pipeline_data,
      jobs = jobs_data,
      actions = {
        details = function(job)
          local full_job, err = api.job(job.id, { cwd = root })
          if not full_job then
            notification.error(err)
            return
          end
          job_details.show({
            job = full_job,
            root = root,
            on_back = function()
              do_show_pipeline(pipeline_data, jobs_data)
            end,
          })
        end,
        logs = function(job)
          jobs_module.logs({ args = job.id, root = root })
        end,
        artifacts = function(job)
          artifacts.download({ job_id = job.id })
        end,
        rerun = function()
          actions.rerun_pipeline(pipeline_data.id)
        end,
        refresh = function()
          local r_p, p_err = api.pipeline(pipeline_data.id, { cwd = root })
          if not r_p then
            notification.error(p_err)
            return
          end
          local r_j, j_err = api.pipeline_jobs(pipeline_data.id, { cwd = root })
          if not r_j then
            notification.error(j_err)
            return
          end
          do_show_pipeline(r_p, r_j)
        end,
      },
      on_back = nil,
    })
  end

  do_show_pipeline(pipeline, pipeline_jobs)
end

local function pick_pipeline(root, callback)
  local pipelines, err = api.pipelines({
    cwd = root,
    per_page = 100,
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
