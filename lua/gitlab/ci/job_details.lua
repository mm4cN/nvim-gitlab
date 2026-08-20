local actions = require("gitlab.ci.actions")
local api = require("gitlab.api")
local artifacts = require("gitlab.ci.artifacts")
local format = require("gitlab.ci.format")
local git = require("gitlab.git")
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

local function current_branch()
  local branch, err = git.branch()

  if not branch then
    notification.error(err)
    return nil
  end

  return branch
end

local function pick_job(root, callback)
  local branch = current_branch()

  if not branch then
    return
  end

  local pipeline, pipeline_err = api.latest_pipeline({
    cwd = root,
    ref = branch,
  })

  if not pipeline then
    notification.error(pipeline_err)
    return
  end

  local jobs, jobs_err = api.pipeline_jobs(pipeline.id, {
    cwd = root,
  })

  if not jobs then
    notification.error(jobs_err)
    return
  end

  if #jobs == 0 then
    notification.error("No jobs found for pipeline: " .. tostring(pipeline.id))
    return
  end

  picker.select(jobs, {
    prompt = "GitLab jobs",
    select_label = "Select job",
    preview = format.job_preview,
    format_item = format.job,
  }, function(job)
    if not job then
      return
    end

    callback(job)
  end)
end

function M.show(opts)
  opts = opts or {}

  local root = opts.root or repo_root()
  if not root then return end
  local project = opts.project

  local function do_show_job(job)
    picker.show_job({
      job = job,
      actions = {
        logs = function()
          require("gitlab.ci.jobs").logs({ args = job.id, root = root, project = project })
        end,
        artifacts = function()
          artifacts.download({ job_id = job.id, root = root, project = project })
        end,
        retry = function()
          actions.retry_job(job.id, { root = root, project = project })
        end,
        play = function()
          if job.status ~= "manual" then
            notification.warn("Job is not manual: " .. tostring(job.status))
            return
          end
          actions.play_job(job.id, { root = root, project = project })
        end,
        refresh = function()
          local refreshed, err = api.job(job.id, { cwd = root, project = project })
          if not refreshed then
            notification.error(err)
            return
          end
          do_show_job(refreshed)
        end,
      },
      on_back = opts.on_back,
    })
  end

  -- Pre-fetched job provided by caller (avoids redundant API call)
  if opts.job then
    do_show_job(opts.job)
    return
  end

  -- Fetch by explicit job_id
  local job_id = opts.job_id
  if job_id and job_id ~= "" then
    local job, err = api.job(job_id, { cwd = root, project = project })
    if not job then
      notification.error(err)
      return
    end
    do_show_job(job)
    return
  end

  -- Let user pick a job
  pick_job(root, function(job)
    local full_job, err = api.job(job.id, { cwd = root })
    if not full_job then
      notification.error(err)
      return
    end
    do_show_job(full_job)
  end)
end

return M
