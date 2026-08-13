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

  if opts.fields then
    for key, value in pairs(opts.fields) do
      vim.list_extend(args, {
        "-f",
        key .. "=" .. tostring(value),
      })
    end
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

function M.pipelines(opts)
  opts = opts or {}

  local query = "per_page=" .. tostring(opts.per_page or 20)

  if opts.page and opts.page > 0 then
    query = query .. "&page=" .. tostring(opts.page)
  end

  if opts.ref and opts.ref ~= "" then
    query = query .. "&ref=" .. vim.uri_encode(opts.ref)
  end

  return M.get("projects/:id/pipelines?" .. query, {
    cwd = opts.cwd,
  })
end

-- parse_spec_inputs extracts spec:inputs from raw .gitlab-ci.yml content.
-- EXPERIMENTAL: GitLab has no REST endpoint for spec:inputs discovery (issue #519944).
-- Supported subset only: 2-space indented YAML, scalar defaults, block-style options lists.
-- Not supported: include: directives, YAML anchors/aliases, block scalars, tabs, array defaults.
local function parse_spec_inputs(content)
  local inputs = {}
  local lines = vim.split(content, "\n", { plain = true })

  local in_spec = false
  local in_inputs = false
  local current = nil
  local in_options = false

  for _, line in ipairs(lines) do
    if line:match("^%s*#") or line:match("^%s*$") then
      -- skip comments and blank lines
    else
      local indent = #line:match("^(%s*)")
      local trimmed = vim.trim(line)

      if indent == 0 then
        in_spec = trimmed == "spec:"
        in_inputs = false
        current = nil
        in_options = false
      elseif in_spec and indent == 2 then
        in_inputs = trimmed == "inputs:"
        current = nil
        in_options = false
      elseif in_inputs and indent == 4 then
        local name = trimmed:match("^([%w_%-]+)%s*:$")
        if name then
          current = { name = name, type = "string", value = "" }
          table.insert(inputs, current)
          in_options = false
        end
      elseif in_inputs and current and indent == 6 then
        local key, val = trimmed:match("^([%w_%-]+)%s*:%s*(.-)%s*$")
        if key == "options" then
          in_options = true
          current.options = {}
        elseif key then
          in_options = false
          val = val:gsub('^["\']', ""):gsub('["\']$', "")
          if key == "default" then
            current.default = val
            current.value = val
          elseif key == "description" then
            current.description = val
          elseif key == "type" then
            current.type = val
          end
        end
      elseif in_inputs and current and in_options and indent == 8 then
        local item = trimmed:match("^%-%s*(.+)$")
        if item then
          item = item:gsub('^["\']', ""):gsub('["\']$', "")
          table.insert(current.options, item)
        end
      end
    end
  end

  return inputs
end

function M.pipeline_inputs(opts)
  opts = opts or {}

  if not opts.ref or opts.ref == "" then
    return nil, "ref is required"
  end

  local path
  if opts.project and opts.project ~= "" then
    path = "projects/" .. opts.project:gsub("/", "%%2F")
        .. "/repository/files/.gitlab-ci.yml/raw?ref=" .. vim.uri_encode(opts.ref)
  else
    path = "projects/:id/repository/files/.gitlab-ci.yml/raw?ref=" .. vim.uri_encode(opts.ref)
  end

  local content, err = glab.run({ "api", path }, { cwd = opts.cwd })

  if not content or content == "" then
    return nil, err or "CI file not found"
  end

  return parse_spec_inputs(content), nil
end

function M.run_pipeline(opts)
  opts = opts or {}

  if not opts.ref or opts.ref == "" then
    return nil, "ref is required"
  end

  return M.request("projects/:id/pipeline", {
    cwd = opts.cwd,
    method = "POST",
    fields = {
      ref = opts.ref,
    },
  })
end

return M
