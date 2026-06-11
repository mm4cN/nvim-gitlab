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

local function current_branch()
  local branch, err = git.branch()
  if not branch then
    notification.error(err)
    return nil
  end

  return branch
end

local function short_sha(sha)
  if not sha or sha == "" then
    return "unknown"
  end

  return string.sub(sha, 1, 8)
end

local function status_icon(status)
  return constants.pipeline_status_icons[status] or "?"
end

local function format_job(job)
  return string.format(
    "  %s %s [%s] #%s",
    status_icon(job.status),
    job.name or "unknown",
    job.status or "unknown",
    tostring(job.id)
  )
end

local function show_pipeline(root, pipeline)
  local jobs, jobs_err = api.pipeline_jobs(pipeline.id, {
    cwd = root,
  })

  if not jobs then
    notification.error(jobs_err)
    return
  end

  local lines = {
    "Pipeline #" .. tostring(pipeline.id),
    "",
    "Status:  " .. status_icon(pipeline.status) .. " " .. tostring(pipeline.status),
    "Ref:     " .. tostring(pipeline.ref),
    "SHA:     " .. short_sha(pipeline.sha),
    "Created: " .. tostring(pipeline.created_at),
    "Updated: " .. tostring(pipeline.updated_at),
    "",
    "Jobs:",
    "",
  }

  if #jobs == 0 then
    table.insert(lines, "  No jobs found")
  else
    for _, job in ipairs(jobs) do
      table.insert(lines, format_job(job))
    end
  end

  buffer.show({
    title = "GitLab Pipeline #" .. tostring(pipeline.id),
    filetype = "gitlab",
    lines = lines,
  })
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

  local branch = current_branch()
  if not branch then
    return
  end

  local pipeline, err = api.latest_pipeline({
    cwd = root,
    ref = branch,
  })

  if not pipeline then
    notification.error(err)
    return
  end

  show_pipeline(root, pipeline)
end

return M
