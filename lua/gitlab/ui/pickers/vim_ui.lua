local buffer = require("gitlab.ui.buffer")
local format = require("gitlab.ci.format")
local navigation = require("gitlab.ui.navigation")
local notification = require("gitlab.ui.notification")

local M = {}

function M.select(items, opts, callback)
  opts = opts or {}

  vim.ui.select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, callback)
end

local function find_job_by_id(jobs, job_id)
  for _, job in ipairs(jobs) do
    if tostring(job.id) == tostring(job_id) then
      return job
    end
  end
  return nil
end

local function job_under_cursor(jobs)
  local job_id = navigation.job_id_under_cursor()
  if not job_id then
    notification.error("No job id under cursor")
    return nil
  end
  local job = find_job_by_id(jobs, job_id)
  if not job then
    notification.error("Job not found: #" .. tostring(job_id))
    return nil
  end
  return job
end

function M.show_pipeline(opts)
  local pipeline = opts.pipeline
  local jobs = opts.jobs

  local lines = {
    "Pipeline #" .. tostring(pipeline.id),
    "",
    "Status: " .. format.status_icon(pipeline.status) .. " " .. tostring(pipeline.status),
    "Ref:     " .. tostring(pipeline.ref),
    "SHA:     " .. format.short_sha(pipeline.sha),
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
      table.insert(lines, format.job(job))
    end
  end

  buffer.show({
    title = "GitLab Pipeline #" .. tostring(pipeline.id),
    filetype = "gitlab",
    lines = lines,
    hints = {
      { key = "r",    label = "Refresh" },
      { key = "<CR>", label = "Details" },
      { key = "L",    label = "Logs" },
      { key = "A",    label = "Artifacts" },
      { key = "R",    label = "Re-run" },
      { key = "b",    label = "Back" },
      { key = "q",    label = "Quit" },
    },
    keymaps = {
      q = buffer.close_current,
      r = buffer.refresh,

      b = buffer.back,

      ["<CR>"] = function()
        local job = job_under_cursor(jobs)
        if job then opts.actions.details(job) end
      end,

      L = function()
        local job = job_under_cursor(jobs)
        if job then opts.actions.logs(job) end
      end,

      A = function()
        local job = job_under_cursor(jobs)
        if job then opts.actions.artifacts(job) end
      end,

      R = function()
        opts.actions.rerun()
      end,
    },
    refresh = function()
      opts.actions.refresh()
    end,
  })
end

function M.show_job(opts)
  local job = opts.job
  local commit = job.commit or {}
  local pipeline = job.pipeline or {}

  local hints = {}
  if job.status == "manual" then
    table.insert(hints, { key = "P", label = "Play" })
  end
  table.insert(hints, { key = "r", label = "Refresh" })
  table.insert(hints, { key = "L", label = "Logs" })
  table.insert(hints, { key = "A", label = "Artifacts" })
  table.insert(hints, { key = "R", label = "Retry" })
  table.insert(hints, { key = "b", label = "Back" })
  table.insert(hints, { key = "q", label = "Quit" })

  local keymaps = {
    q = buffer.close_current,
    r = buffer.refresh,

    b = buffer.back,

    L = function() opts.actions.logs() end,
    A = function() opts.actions.artifacts() end,
    R = function() opts.actions.retry() end,
  }

  if job.status == "manual" then
    keymaps.P = function() opts.actions.play() end
  end

  buffer.push({
    title = "GitLab Job #" .. tostring(job.id),
    filetype = "gitlab",
    lines = {
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
    },
    hints = hints,
    keymaps = keymaps,
    refresh = function()
      opts.actions.refresh()
    end,
  })
end

return M
