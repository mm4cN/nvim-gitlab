local glab = require("gitlab.glab")
local yq = require("gitlab.ci.yq")

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
    query = query .. "&ref=" .. vim.uri_encode(ref, "rfc2396")
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
    query = query .. "&ref=" .. vim.uri_encode(opts.ref, "rfc2396")
  end

  return M.get(project_prefix(opts) .. "/pipelines?" .. query, {
    cwd = opts.cwd,
  })
end

function M.project(opts)
  opts = opts or {}

  if not opts.project or opts.project == "" then
    return nil, "project is required"
  end

  local project, err = M.get(project_prefix(opts), { cwd = opts.cwd })
  if err then
    return nil, err
  end
  if type(project) ~= "table" then
    return nil, "Project metadata is unavailable"
  end
  if type(project.id) ~= "number" then
    return nil, "Project metadata is missing id"
  end
  if type(project.name) ~= "string" or project.name == "" then
    return nil, "Project metadata is missing name"
  end
  if not project.path_with_namespace or project.path_with_namespace == "" then
    return nil, "Project metadata is missing path_with_namespace"
  end
  if not project.default_branch or project.default_branch == "" then
    return nil, "Project metadata is missing default_branch"
  end

  return {
    id = project.id,
    name = project.name,
    path_with_namespace = project.path_with_namespace,
    default_branch = project.default_branch,
  }, nil
end

local function is_map(value)
  return type(value) == "table" and not vim.islist(value)
end

local function sorted_keys(value)
  local keys = vim.tbl_keys(value)
  table.sort(keys)
  return keys
end

local function scalar(value, context)
  if value == nil or value == vim.NIL then
    return nil
  end
  local value_type = type(value)
  if value_type == "string" then
    return value
  end
  if value_type == "number" or value_type == "boolean" then
    return tostring(value)
  end
  return nil, "Unsupported YAML value for " .. context .. ": expected a scalar, got " .. value_type
end

local function scalar_options(value, context)
  if value == nil or value == vim.NIL then
    return nil, nil
  end
  if type(value) ~= "table" or not vim.islist(value) then
    return nil, "Unsupported YAML value for " .. context .. ": expected a list, got " .. type(value)
  end

  local options = {}
  for i, option in ipairs(value) do
    local normalized, err = scalar(option, context .. "[" .. i .. "]")
    if err then
      return nil, err
    end
    table.insert(options, normalized)
  end
  return options, nil
end

local function parse_spec_inputs(documents)
  local inputs = {}
  for _, document in ipairs(documents) do
    if is_map(document) and document.spec ~= nil and document.spec ~= vim.NIL then
      if not is_map(document.spec) then
        return nil, "Unsupported YAML value for spec: expected a map"
      end
      local raw_inputs = document.spec.inputs
      if raw_inputs ~= nil and raw_inputs ~= vim.NIL then
        if not is_map(raw_inputs) then
          return nil, "Unsupported YAML value for spec.inputs: expected a map"
        end
        for _, name in ipairs(sorted_keys(raw_inputs)) do
          local raw = raw_inputs[name]
          if raw == vim.NIL then raw = {} end
          if not is_map(raw) then
            return nil, "Unsupported YAML value for spec input '" .. name .. "': expected a map"
          end
          local input_type, type_err = scalar(raw.type, "spec input '" .. name .. "' type")
          if type_err then return nil, type_err end
          local default, default_err = scalar(raw.default, "spec input '" .. name .. "' default")
          if default_err then return nil, default_err end
          local description, description_err = scalar(raw.description, "spec input '" .. name .. "' description")
          if description_err then return nil, description_err end
          local options, options_err = scalar_options(raw.options, "spec input '" .. name .. "' options")
          if options_err then return nil, options_err end

          table.insert(inputs, {
            name = name,
            type = input_type or "string",
            default = default,
            description = description,
            options = options,
            value = default or "",
          })
        end
      end
    end
  end
  return inputs, nil
end

function M.latest_pipeline_async(opts, callback)
  opts = opts or {}

  local ref = opts.ref
  local query = "per_page=1"

  if ref and ref ~= "" then
    query = query .. "&ref=" .. vim.uri_encode(ref, "rfc2396")
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

local function parse_legacy_variables(documents)
  local vars = {}
  for _, document in ipairs(documents) do
    if is_map(document) and document.variables ~= nil and document.variables ~= vim.NIL then
      if not is_map(document.variables) then
        return nil, "Unsupported YAML value for variables: expected a map"
      end
      for _, key in ipairs(sorted_keys(document.variables)) do
        local raw = document.variables[key]
        if is_map(raw) then
          local description, description_err = scalar(raw.description, "legacy variable '" .. key .. "' description")
          if description_err then return nil, description_err end
          if raw.value ~= nil and description and description ~= "" then
            local value, value_err = scalar(raw.value, "legacy variable '" .. key .. "' value")
            if value_err then return nil, value_err end
            local options, options_err = scalar_options(raw.options, "legacy variable '" .. key .. "' options")
            if options_err then return nil, options_err end
            table.insert(vars, {
              key = key,
              value = value,
              description = description,
              options = options,
            })
          end
        end
      end
    end
  end
  return vars, nil
end

function M.pipeline_inputs(opts)
  opts = opts or {}

  if not opts.ref or opts.ref == "" then
    return nil, "ref is required"
  end

  -- Raw file is required for spec:inputs — ci/lint strips the spec: block from merged_yaml.
  local raw_path = project_prefix(opts) .. "/repository/files/.gitlab-ci.yml/raw?ref=" .. vim.uri_encode(opts.ref, "rfc2396")
  local content, err = glab.run({ "api", raw_path }, { cwd = opts.cwd })

  if not content or content == "" then
    return nil, err or "CI file not found"
  end

  -- ci/lint merged_yaml expands include: directives for legacy described variables.
  -- Degrade gracefully if this secondary fetch fails.
  local lint_path = project_prefix(opts) .. "/ci/lint?content_ref=" .. vim.uri_encode(opts.ref, "rfc2396")
  local lint_result, _ = M.get(lint_path, { cwd = opts.cwd })
  local merged = (lint_result and lint_result.merged_yaml ~= "" and lint_result.merged_yaml) or content

  local raw_documents, parse_err = yq.parse_documents(content, { cwd = opts.cwd, multiple = true })
  if not raw_documents then
    return nil, parse_err
  end
  local inputs, inputs_err = parse_spec_inputs(raw_documents)
  if not inputs then
    return nil, inputs_err
  end

  local merged_documents, merged_err = yq.parse_documents(merged, { cwd = opts.cwd, multiple = true })
  if not merged_documents then
    return nil, merged_err
  end
  local variables, variables_err = parse_legacy_variables(merged_documents)
  if not variables then
    return nil, variables_err
  end

  return inputs, nil, variables
end

return M
