local glab = require("gitlab.glab")

local M = {}

-- Returns the project URL prefix for path construction.
-- Explicit project always wins; absent falls back to the glab :id placeholder.
local function project_prefix(opts)
  if opts and opts.project and opts.project ~= "" then
    return "projects/" .. opts.project:gsub("/", "%%2F")
  end
  return "projects/:id"
end

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

  local pipelines, err = M.get(project_prefix(opts) .. "/pipelines?" .. query, {
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

  return M.get(project_prefix(opts) .. "/pipelines/" .. tostring(pipeline_id) .. "/jobs", {
    cwd = opts.cwd,
  })
end

function M.pipeline(pipeline_id, opts)
  opts = opts or {}

  if not pipeline_id then
    return nil, "pipeline_id is required"
  end

  return M.get(project_prefix(opts) .. "/pipelines/" .. tostring(pipeline_id), {
    cwd = opts.cwd,
  })
end

function M.job(job_id, opts)
  opts = opts or {}

  if not job_id then
    return nil, "job_id is required"
  end

  return M.get(project_prefix(opts) .. "/jobs/" .. tostring(job_id), {
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

  return M.get(project_prefix(opts) .. "/pipelines?" .. query, {
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

function M.latest_pipeline_async(opts, callback)
  opts = opts or {}

  local ref = opts.ref
  local query = "per_page=1"

  if ref and ref ~= "" then
    query = query .. "&ref=" .. ref
  end

  glab.run_json_async({ "api", project_prefix(opts) .. "/pipelines?" .. query }, {
    cwd = opts.cwd,
  }, function(pipelines, err)
    if err then
      callback(nil, err)
      return
    end
    if not pipelines or #pipelines == 0 then
      callback(nil, "No pipeline found")
      return
    end
    callback(pipelines[1], nil)
  end)
end

function M.variables(opts)
  opts = opts or {}
  return M.get(project_prefix(opts) .. "/variables?per_page=100", { cwd = opts.cwd })
end

function M.branches(opts)
  opts = opts or {}

  if not opts.project or opts.project == "" then
    return nil, "project is required"
  end

  local branches, err = M.get(
    project_prefix(opts) .. "/repository/branches?per_page=100",
    { cwd = opts.cwd }
  )

  if err then
    return nil, err
  end

  if not branches then
    return {}, nil
  end

  local names = {}
  for _, b in ipairs(branches) do
    if b.name and b.name ~= "" then
      table.insert(names, b.name)
    end
  end

  return names, nil
end

-- parse_legacy_variables extracts top-level variables: entries that carry both
-- value: and description: sub-keys (legacy pipeline-variable convention).
-- Inline assignments (KEY: value) and entries without a description are excluded.
-- Only 2-space indentation is supported; tabs are not.
local function parse_legacy_variables(content)
  local vars = {}
  local lines = vim.split(content, "\n", { plain = true })

  local in_variables = false
  local current_name = nil
  local current_value = nil
  local current_description = nil

  local function commit()
    if current_name and current_value ~= nil and current_description and current_description ~= "" then
      table.insert(vars, { key = current_name, value = current_value, description = current_description })
    end
    current_name = nil
    current_value = nil
    current_description = nil
  end

  for _, line in ipairs(lines) do
    if not (line:match("^%s*#") or line:match("^%s*$")) then
      local indent = #line:match("^(%s*)")
      local trimmed = vim.trim(line)

      if indent == 0 then
        commit()
        in_variables = trimmed == "variables:"
      elseif in_variables and indent == 2 then
        commit()
        -- block-form only: trailing colon with no inline value
        local name = trimmed:match("^([%w_%-]+)%s*:$")
        if name then
          current_name = name
        end
      elseif in_variables and current_name and indent == 4 then
        local key, val = trimmed:match("^([%w_%-]+)%s*:%s*(.-)%s*$")
        if key and val then
          val = val:gsub('^["\']', ""):gsub('["\']$', "")
          if key == "value" then
            current_value = val
          elseif key == "description" then
            current_description = val
          end
        end
      end
    end
  end
  commit()

  return vars
end

function M.pipeline_inputs(opts)
  opts = opts or {}

  if not opts.ref or opts.ref == "" then
    return nil, "ref is required"
  end

  -- Raw file is required for spec:inputs — ci/lint strips the spec: block from merged_yaml.
  local raw_path = project_prefix(opts) .. "/repository/files/.gitlab-ci.yml/raw?ref=" .. vim.uri_encode(opts.ref)
  local content, err = glab.run({ "api", raw_path }, { cwd = opts.cwd })

  if not content or content == "" then
    return nil, err or "CI file not found"
  end

  -- ci/lint merged_yaml expands include: directives for legacy described variables.
  -- Degrade gracefully if this secondary fetch fails.
  local lint_path = project_prefix(opts) .. "/ci/lint?content_ref=" .. vim.uri_encode(opts.ref)
  local lint_result, _ = M.get(lint_path, { cwd = opts.cwd })
  local merged = (lint_result and lint_result.merged_yaml ~= "" and lint_result.merged_yaml) or content

  return parse_spec_inputs(content), nil, parse_legacy_variables(merged)
end

function M.run_pipeline(opts)
  opts = opts or {}

  if not opts.ref or opts.ref == "" then
    return nil, "ref is required"
  end

  return M.request(project_prefix(opts) .. "/pipeline", {
    cwd = opts.cwd,
    method = "POST",
    fields = {
      ref = opts.ref,
    },
  })
end

return M
