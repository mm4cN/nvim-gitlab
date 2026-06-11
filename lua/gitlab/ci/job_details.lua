local api = require("gitlab.api")
local git = require("gitlab.git")
local buffer = require("gitlab.ui.buffer")
local notification = require("gitlab.ui.notification")
local constants = require("gitlab.constants")

local M = {}

local function repo_root()
  local root, err = git.root()
  if not root then
    notification.error(err)
    return nil
  end

  return root
end

local function status_icon(status)
  return constants.pipeline_status_icons[status] or "?"
end

local function value(v)
  if v == nil or v == "" then
    return "unknown"
  end

  return tostring(v)
end

local function short_sha(sha)
  if not sha or sha == "" then
    return "unknown"
  end

  return string.sub(sha, 1, 8)
end

local function format_duration(seconds)
  if not seconds then
    return "unknown"
  end

  seconds = math.floor(seconds)

  local minutes = math.floor(seconds / 60)
  local rest = seconds % 60

  if minutes > 0 then
    return string.format("%dm%02ds", minutes, rest)
  end

  return tostring(rest) .. "s"
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
    "Name:      " .. value(job.name),
    "Status:    " .. status_icon(job.status) .. " " .. value(job.status),
    "Stage:     " .. value(job.stage),
    "Ref:       " .. value(job.ref),
    "Duration:  " .. format_duration(job.duration),
    "Started:   " .. value(job.started_at),
    "Finished:  " .. value(job.finished_at),
    "",
    "Pipeline:",
    "  ID:      " .. value(pipeline.id),
    "  Status:  " .. status_icon(pipeline.status) .. " " .. value(pipeline.status),
    "  Ref:     " .. value(pipeline.ref),
    "",
    "Commit:",
    "  SHA:     " .. short_sha(commit.id or commit.sha),
    "  Title:   " .. value(commit.title),
    "  Author:  " .. value(commit.author_name),
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
    },
  })
end

return M
