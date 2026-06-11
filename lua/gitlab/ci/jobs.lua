local git = require("gitlab.git")
local glab = require("gitlab.glab")
local buffer = require("gitlab.ui.buffer")
local notification = require("gitlab.ui.notification")
local picker = require("gitlab.ui.picker")
local constants = require("gitlab.constants")
local api = require("gitlab.api")

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

local function show_logs(root, job_id)
  local output, err = glab.run({
    "ci",
    "trace",
    tostring(job_id),
  }, {
    cwd = root,
  })

  if err then
    notification.error(err)
    return
  end

  buffer.show({
    title = "GitLab Job " .. tostring(job_id),
    filetype = "log",
    lines = vim.split(output, "\n", { plain = true }),
  })
end

local function format_job(job)
  local icon = constants.pipeline_status_icons[job.status] or "?"
  return string.format(
    "%s %s [%s] #%s",
    icon,
    job.name or "unknown",
    job.status or "unknown",
    tostring(job.id)
  )
end

function M.logs(opts)
  local root = repo_root()
  if not root then
    return
  end

  local job_id = opts and opts.args or ""

  if job_id ~= "" then
    show_logs(root, job_id)
    return
  end

  local branch = current_branch()
  if not branch then
    return
  end

  local pipeline, pipeline_error = api.latest_pipeline({ cwd = root, ref = branch, })

  if not pipeline then
    notification.error(pipeline_error)
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
    prompt = "GitLab job logs",
    format_item = format_job,
  }, function(job)
    if not job then
      return
    end

    show_logs(root, job.id)
  end)
end

function M.retry(opts)
  local root = repo_root()
  if not root then
    return
  end

  local job_id = opts and opts.args or ""

  if job_id == "" then
    vim.ui.input({ prompt = "GitLab job id: " }, function(input)
      if not input or input == "" then
        return
      end

      M.retry({ args = vim.trim(input) })
    end)

    return
  end

  local output, err = glab.run({
    "job",
    "retry",
    tostring(job_id),
  }, {
    cwd = root,
  })

  if err then
    notification.error(err)
    return
  end

  buffer.show({
    title = "GitLab Job Retry",
    filetype = "text",
    lines = vim.split(output, "\n", { plain = true }),
  })
end

return M
