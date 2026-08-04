local actions = require("gitlab.ci.actions")
local artifacts = require("gitlab.ci.artifacts")
local format = require("gitlab.ci.format")
local git = require("gitlab.git")
local glab = require("gitlab.glab")
local buffer = require("gitlab.ui.buffer")
local notification = require("gitlab.ui.notification")
local picker = require("gitlab.ui.picker")
local api = require("gitlab.api")
local navigation = require("gitlab.ui.navigation")

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

  local hints = {
    { key = "b", label = "Back" },
    { key = "q", label = "Quit" },
  }

  buffer.push({
    title = "GitLab Job " .. tostring(job_id),
    filetype = "log",
    lines = clean_logs(output),
    hints = hints,
    keymaps = {
      q = buffer.close_current,
      b = buffer.back,
    },
  })
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

  local pipeline_id = pipeline.id

  local function build_view(pipeline_data, jobs_data)
    local lines = {
      "Jobs for Pipeline #" .. tostring(pipeline_data.id),
      "",
      "Ref:    " .. tostring(pipeline_data.ref),
      "Status: " .. tostring(pipeline_data.status),
      "",
    }

    for _, job in ipairs(jobs_data) do
      table.insert(lines, format.job(job))
    end

    local hints = {
      { key = "r",    label = "Refresh" },
      { key = "<CR>", label = "Details" },
      { key = "L",    label = "Logs" },
      { key = "A",    label = "Artifacts" },
      { key = "R",    label = "Retry" },
      { key = "b",    label = "Back" },
      { key = "q",    label = "Quit" },
    }

    local function refresh_view()
      local refreshed_pipeline, refresh_pipeline_err = api.pipeline(pipeline_id, {
        cwd = root,
      })

      if not refreshed_pipeline then
        notification.error(refresh_pipeline_err)
        return
      end

      local refreshed_jobs, jobs_err = api.pipeline_jobs(pipeline_id, {
        cwd = root,
      })

      if not refreshed_jobs then
        notification.error(jobs_err)
        return
      end

      buffer.replace(build_view(refreshed_pipeline, refreshed_jobs))
    end

    return {
      title = "GitLab Jobs",
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
          require("gitlab.ci.job_details").show({
            job_id = job_id,
          })
        end,

        L = function()
          local job_id = navigation.job_id_under_cursor()
          if not job_id then
            notification.error("No job id under cursor")
            return
          end
          show_logs(root, job_id)
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
          local job_id = navigation.job_id_under_cursor()

          if not job_id then
            notification.error("No job id under cursor")

            return
          end

          actions.retry_job(job_id)
        end,
      },
      refresh = refresh_view,
    }
  end

  local jobs, jobs_err = api.pipeline_jobs(pipeline.id, {
    cwd = root,
  })

  if not jobs then
    notification.error(jobs_err)
    return
  end

  buffer.show(build_view(pipeline, jobs))
end

return M
