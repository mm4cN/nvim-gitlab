local git = require("gitlab.git")
local glab = require("gitlab.glab")
local buffer = require("gitlab.ui.buffer")
local notification = require("gitlab.ui.notification")
local picker = require("gitlab.ui.picker")
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

local function latest_pipeline(root, branch)
  local pipelines, err = glab.run_json({
    "api",
    "projects/:id/pipelines?ref=" .. branch .. "&per_page=1",
  }, {
    cwd = root,
  })

  if err then
    notification.error(err)
    return nil
  end

  if not pipelines or #pipelines == 0 then
    notification.error("No pipeline found for branch: " .. branch)
    return nil
  end

  return pipelines[1]
end

local function pipeline_jobs(root, pipeline_id)
  local jobs, err = glab.run_json({
    "api",
    "projects/:id/pipelines/" .. tostring(pipeline_id) .. "/jobs",
  }, {
    cwd = root,
  })

  if err then
    notification.error(err)
    return nil
  end

  if not jobs or #jobs == 0 then
    notification.error("No jobs found for pipeline: " .. tostring(pipeline_id))
    return nil
  end

  return jobs
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

  local pipeline = latest_pipeline(root, branch)
  if not pipeline then
    return
  end

  local jobs = pipeline_jobs(root, pipeline.id)
  if not jobs then
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
