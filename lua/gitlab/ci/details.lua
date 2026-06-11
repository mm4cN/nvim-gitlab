local api = require("gitlab.api")
local actions = require("gitlab.ci.actions")
local artifacts = require("gitlab.ci.artifacts")
local buffer = require("gitlab.ui.buffer")
local constants = require("gitlab.constants")
local git = require("gitlab.git")
local job_details = require("gitlab.ci.job_details")
local jobs_module = require("gitlab.ci.jobs")
local navigation = require("gitlab.ui.navigation")
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
  local pipeline_jobs, jobs_err = api.pipeline_jobs(pipeline.id, {
    cwd = root,
  })

  if not pipeline_jobs then
    notification.error(jobs_err)
    return
  end

  local lines = {
    "Pipeline #" .. tostring(pipeline.id),
    "",
    "Status: " .. status_icon(pipeline.status) .. " " .. tostring(pipeline.status),
    "Ref:     " .. tostring(pipeline.ref),
    "SHA:     " .. short_sha(pipeline.sha),
    "Created: " .. tostring(pipeline.created_at),
    "Updated: " .. tostring(pipeline.updated_at),
    "",
    "Jobs:",
    "",
  }

  if #pipeline_jobs == 0 then
    table.insert(lines, "  No jobs found")
  else
    for _, job in ipairs(pipeline_jobs) do
      table.insert(lines, format_job(job))
    end
  end

  local hints = {
    { key = "<CR>", label = "Details" },
    { key = "L",    label = "Logs" },
    { key = "A",    label = "Artifacts" },
    { key = "R",    label = "Re-run" },
    { key = "b",    label = "Back" },
    { key = "q",    label = "Quit" },
  }

  buffer.show({
    title = "GitLab Pipeline #" .. tostring(pipeline.id),
    filetype = "gitlab",
    lines = lines,
    hints = hints,

    keymaps = {
      q = buffer.close_current,
      b = buffer.back,

      ["<CR>"] = function()
        local job_id = navigation.job_id_under_cursor()

        if not job_id then
          notification.error("No job id under cursor")
          return
        end

        job_details.show({
          job_id = job_id,
        })
      end,

      L = function()
        local job_id = navigation.job_id_under_cursor()

        if not job_id then
          notification.error("No job id under cursor")
          return
        end

        jobs_module.logs({
          args = job_id,
        })
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
        actions.rerun_pipeline(pipeline.id)
      end,
    },
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
