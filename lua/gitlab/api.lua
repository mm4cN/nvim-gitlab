local glab = require("gitlab.glab")

local M = {}

function M.request(path, opts)
  opts = opts or {}
  local args = { "api", path }

  if opts.method then
    vim.list_extend(args, {
      "--method",
      opts.method,
    })
  end

  return glab.run_json(args, {
    cwd = opts.cwd,
  })
end

function M.get(path, opts)
  return M.request(path, opts)
end

function M.latest_pipeline(opts)
  opts = opts or {}

  local ref = opts.ref
  local query = "per_page=1"

  if ref and ref ~= "" then
    query = query .. "&ref=" .. ref
  end

  local pipelines, err = M.get("projects/:id/pipelines?" .. query, {
    cwd = opts.cwd,
  })

  if err then
    return nil, err
  end

  if not pipelines or #pipelines == 0 then
    return nil, "No pipeline found"
  end

  return pipelines[1], nil
end

function M.pipeline_jobs(pipeline_id, opts)
  opts = opts or {}

  if not pipeline_id then
    return nil, "pipeline_id is required"
  end

  return M.get("projects/:id/pipelines/" .. tostring(pipeline_id) .. "/jobs", {
    cwd = opts.cwd,
  })
end

function M.pipeline(pipeline_id, opts)
  opts = opts or {}

  if not pipeline_id then
    return nil, "pipeline_id is required"
  end

  return M.get("projects/:id/pipelines/" .. tostring(pipeline_id), {
    cwd = opts.cwd,
  })
end

function M.job(job_id, opts)
  opts = opts or {}

  if not job_id then
    return nil, "job_id is required"
  end

  return M.get("projects/:id/jobs/" .. tostring(job_id), {
    cwd = opts.cwd,
  })
end

return M
