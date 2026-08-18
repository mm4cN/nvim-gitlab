local api = require("gitlab.api")
local buffer = require("gitlab.ui.buffer")
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

function M.retry_job(job_id)
  if not job_id or job_id == "" then
    notification.error("job_id is required")
    return
  end

  local root = repo_root()
  if not root then
    return
  end

  notification.info("Retrying job #" .. tostring(job_id) .. "...")

  local _, err = api.request("projects/:id/jobs/" .. tostring(job_id) .. "/retry", {
    cwd = root,
    method = "POST",
  })

  if err then
    notification.error(err)
    return
  end

  notification.info("Job #" .. tostring(job_id) .. " retry requested")
  buffer.refresh()
end

function M.play_job(job_id)
  if not job_id or job_id == "" then
    notification.error("job_id is required")
    return
  end

  local root = repo_root()
  if not root then
    return
  end

  notification.info("Playing job #" .. tostring(job_id) .. "...")

  local _, err = api.request("projects/:id/jobs/" .. tostring(job_id) .. "/play", {
    cwd = root,
    method = "POST",
  })

  if err then
    notification.error(err)
    return
  end

  notification.info("Job #" .. tostring(job_id) .. " play requested")
  buffer.refresh()
end

function M.rerun_pipeline(pipeline_id)
  if not pipeline_id or pipeline_id == "" then
    notification.error("pipeline_id is required")
    return
  end

  local root = repo_root()
  if not root then
    return
  end

  local pipeline, err = api.pipeline(pipeline_id, {
    cwd = root,
  })

  if not pipeline then
    notification.error(err)
    return
  end

  local ref = pipeline.ref

  if not ref or ref == "" then
    notification.error("Pipeline ref is missing")
    return
  end

  notification.info("Rerunning pipeline on " .. ref .. "...")

  local output, run_err = require("gitlab.glab").run({
    "pipeline",
    "run",
    "-b",
    ref,
  }, {
    cwd = root,
  })

  if run_err then
    notification.error(run_err)
    return
  end

  notification.info(output ~= "" and output or "Pipeline rerun requested: " .. ref)
  buffer.refresh()
end

return M
