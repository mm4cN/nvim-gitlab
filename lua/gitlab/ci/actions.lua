local api = require("gitlab.api")
local config = require("gitlab.config")
local git = require("gitlab.git")
local confirm = require("gitlab.ui.confirm")
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

  local _, err = api.request("projects/:id/jobs/" .. tostring(job_id) .. "/retry", {
    cwd = root,
    method = "POST",
  })

  if err then
    notification.error(err)
    return
  end

  notification.info("Job retry requested: #" .. tostring(job_id))
end

function M.retry_pipeline_jobs(pipeline_id)
  if not pipeline_id or pipeline_id == "" then
    notification.error("pipeline_id is required")
    return
  end

  local root = repo_root()
  if not root then
    return
  end

  local jobs, jobs_err = api.pipeline_jobs(pipeline_id, {
    cwd = root,
  })

  if not jobs then
    notification.error(jobs_err)
    return
  end

  local retried = 0
  local failed = 0

  for _, job in ipairs(jobs) do
    if job.status == "failed" or job.status == "canceled" then
      local _, err = api.request("projects/:id/jobs/" .. tostring(job.id) .. "/retry", {
        cwd = root,
        method = "POST",
      })

      if err then
        failed = failed + 1
      else
        retried = retried + 1
      end
    end
  end

  if retried == 0 and failed == 0 then
    notification.info("No failed or canceled jobs to retry")
    return
  end

  if failed > 0 then
    notification.error("Retried " .. retried .. " job(s), failed to retry " .. failed)
    return
  end

  notification.info("Retried " .. retried .. " job(s)")
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
end

return M
