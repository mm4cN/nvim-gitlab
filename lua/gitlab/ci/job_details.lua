local actions = require("gitlab.ci.actions")
local api = require("gitlab.api")
local artifacts = require("gitlab.ci.artifacts")
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

function M.show(opts)
  opts = opts or {}

  local job_id = opts.job_id

  if not job_id or job_id == "" then
    notification.error("job_id is required")
    return
  end

  local root = repo_root()
  if not root then
    return
  end

  local job, err = api.job(job_id, {
    cwd = root,
  })

  if not job then
    notification.error(err)
    return
  end

  local commit = job.commit or {}
  local pipeline = job.pipeline or {}

  local lines = {
    "Job #" .. tostring(job.id),
    "",
    "Name:      " .. format.value(job.name),
    "Status:    " .. format.status_icon(job.status) .. " " .. format.value(job.status),
    "Stage:     " .. format.value(job.stage),
    "Ref:       " .. format.value(job.ref),
    "Duration:  " .. format.duration(job.duration),
    "Started:   " .. format.value(job.started_at),
    "Finished:  " .. format.value(job.finished_at),
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
    "  :GitlabJobLogs " .. tostring(job.id),
    "  :GitlabJobRetry " .. tostring(job.id),
  }

  buffer.push({
    title = "GitLab Job #" .. tostring(job.id),
    filetype = "gitlab",
    lines = lines,
    keymaps = {
      q = buffer.close_current,
      b = buffer.back,

      A = function()
        artifacts.download({
          job_id = job.id,
        })
      end,

      R = function()
        actions.retry_job(job.id)
      end,
    },
  })
end

return M
