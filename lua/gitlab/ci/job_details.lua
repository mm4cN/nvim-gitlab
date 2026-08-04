local actions = require("gitlab.ci.actions")
local api = require("gitlab.api")
local artifacts = require("gitlab.ci.artifacts")
local buffer = require("gitlab.ui.buffer")
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

  local job_id = opts.job_id
  local root = repo_root()

  if not root then
    return
  end

  if not job_id or job_id == "" then
    pick_job(root, function(job)
      M.show({
        job_id = job.id,
      })
    end)
    return
  end

  local function build_view(job_data)
    local commit = job_data.commit or {}
    local pipeline = job_data.pipeline or {}

    local lines = {
      "Job #" .. tostring(job_data.id),
      "",
      "Name:      " .. format.value(job_data.name),
      "Status:    " .. format.status_icon(job_data.status) .. " " .. format.value(job_data.status),
      "Stage:     " .. format.value(job_data.stage),
      "Ref:       " .. format.value(job_data.ref),
      "Duration:  " .. format.duration(job_data.duration),
      "Started:   " .. format.value(job_data.started_at),
      "Finished:  " .. format.value(job_data.finished_at),
      "",
      "Pipeline:",
      "  ID:      " .. format.value(pipeline.id),
      "  Status:  " .. format.status_icon(pipeline.status) .. " " .. format.value(pipeline.status),
      "  Ref:     " .. format.value(pipeline.ref),
      "",
      "Commit:",
      "  SHA:     " .. format.short_sha(commit.id or commit.sha),
      "  Title:   " .. format.value(commit.title),
      "  Author:  " .. format.value(commit.author_name),
      "",
      "Actions:",
      "  :GitlabJobLogs " .. tostring(job_data.id),
      "  :GitlabJobRetry " .. tostring(job_data.id),
    }

    local function refresh_view()
      local refreshed_job, err = api.job(job_id, {
        cwd = root,
      })

      if not refreshed_job then
        notification.error(err)
        return
      end

      buffer.replace(build_view(refreshed_job))
    end

    return {
      title = "GitLab Job #" .. tostring(job_data.id),
      filetype = "gitlab",
      lines = lines,
      keymaps = {
        q = buffer.close_current,
        b = buffer.back,
        r = buffer.refresh,

        A = function()
          artifacts.download({
            job_id = job_data.id,
          })
        end,

        R = function()
          actions.retry_job(job_data.id)
        end,
      },
      refresh = refresh_view,
    }
  end

  local job, err = api.job(job_id, {
    cwd = root,
  })

  if not job then
    notification.error(err)
    return
  end

  buffer.push(build_view(job))
end

return M
