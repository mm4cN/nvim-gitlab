local actions = require("gitlab.ci.actions")
local artifacts = require("gitlab.ci.artifacts")
local format = require("gitlab.ci.format")
local git = require("gitlab.git")
local glab = require("gitlab.glab")
local job_details = require("gitlab.ci.job_details")
local notification = require("gitlab.ui.notification")
local picker = require("gitlab.ui.picker")
local api = require("gitlab.api")
local log_buffer = require("gitlab.ci.log_buffer")

local M = {}

local function strip_ansi(line)
  line = line:gsub("\27%[[0-9;?]*[ -/]*[@-~]", "")
  line = line:gsub("\27%][^\7]*\7", "")
  return line
end

local function strip_gitlab_prefix(line)
  -- 2026-06-11T20:13:01.614647Z 00O something
  line = line:gsub("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z%s+%d%d[OE]%s?", "")
  return line
end

local function clean_section_marker(line)
  line = line:gsub("^section_start:%d+:[%w_%-]+%s*", "")
  line = line:gsub("^section_end:%d+:[%w_%-]+%s*", "")
  return line
end

local function clean_log_line(line)
  line = strip_ansi(line)
  line = strip_gitlab_prefix(line)
  line = clean_section_marker(line)
  line = line:gsub("^%+%s*", "")
  return vim.trim(line)
end

local function clean_logs(output)
  local cleaned = {}

  for _, line in ipairs(vim.split(output, "\n", { plain = true })) do
    local clean = clean_log_line(line)

    if clean ~= "" then
      table.insert(cleaned, clean)
    end
  end

  return cleaned
end

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

  local lines = clean_logs(output)

  log_buffer.open(job_id, lines)
end

function M.logs(opts)
  local root = (opts and opts.root) or repo_root()
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
    select_label = "Open logs",
    format_item = format.job,
    preview = format.job_preview,
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

  if job_id ~= "" then
    actions.retry_job(job_id)
    return
  end

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
    prompt = "GitLab job retry",
    select_label = "Retry job",
    format_item = format.job,
    preview = format.job_preview,
  }, function(job)
    if not job then
      return
    end

    actions.retry_job(job.id)
  end)
end

function M.list()
  local root = repo_root()
  if not root then
    return
  end

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

  local do_show_jobs -- forward declaration

  do_show_jobs = function(pipeline_data, jobs_data)
    picker.show_jobs({
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
              do_show_jobs(pipeline_data, jobs_data)
            end,
          })
        end,
        logs = function(job)
          show_logs(root, job.id)
        end,
        artifacts = function(job)
          artifacts.download({ job_id = job.id })
        end,
        retry = function(job)
          actions.retry_job(job.id)
        end,
        play = function(job)
          if job.status ~= "manual" then
            notification.warn("Job is not manual: " .. tostring(job.status))
            return
          end
          actions.play_job(job.id)
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
          do_show_jobs(r_p, r_j)
        end,
      },
      on_back = nil,
    })
  end

  do_show_jobs(pipeline, jobs)
end

return M
