local config = require("gitlab.config")
local process = require("gitlab.util.process")

local M = {}

local function cmd(args)
  return vim.list_extend({ config.options.glab_binary }, args)
end

function M.run(args, opts)
  return process.run(cmd(args), opts)
end

function M.run_json(args, opts)
  return process.run_json(cmd(args), opts)
end

function M.api_json(path, opts)
  opts = opts or {}

  local args = { "api", path }

  if opts.method then
    vim.list_extend(args, { "--method", opts.method })
  end

  if opts.fields then
    for key, value in pairs(opts.fields) do
      vim.list_extend(args, { "-f", key .. "=" .. tostring(value) })
    end
  end

  return M.run_json(args, {
    cwd = opts.cwd,
  })
end

-- format_input encodes a single pipeline input for glab ci run --input.
-- GitLab spec:inputs types: string, number, boolean, array.
-- glab typed syntax: key:value (string), key:int(n), key:float(n), key:bool(v), key:array(a,b).
-- For number: validated with tonumber(), integer literal pattern ^[+-]?%d+$ selects int, else float.
-- Array values must be comma-separated strings; YAML sequences and JSON arrays return an error.
local function format_input(input)
  local name = input.name
  if not name or name == "" then
    return nil, "pipeline input is missing a name"
  end

  local value = tostring(input.value or "")
  local t = input.type or "string"

  if t == "number" then
    if tonumber(value) == nil then
      return nil, "invalid number value for '" .. name .. "': " .. value
    end
    if value:match("^[+-]?%d+$") then
      return name .. ":int(" .. value .. ")", nil
    else
      return name .. ":float(" .. value .. ")", nil
    end
  elseif t == "boolean" then
    if value ~= "true" and value ~= "false" then
      return nil, "invalid boolean value for '" .. name .. "': expected 'true' or 'false', got '" .. value .. "'"
    end
    return name .. ":bool(" .. value .. ")", nil
  elseif t == "array" then
    if value == "" then
      return nil, "empty array value for '" .. name .. "': use comma-separated values (e.g. a,b,c)"
    end
    if value:match("^%s*%-") or value:match("^%s*%[") then
      return nil, "unsupported array value for '" .. name .. "': use comma-separated values (e.g. a,b,c)"
    end
    return name .. ":array(" .. value .. ")", nil
  else
    return name .. ":" .. value, nil
  end
end

-- run_pipeline uses `glab ci run` to support cross-project execution and typed pipeline inputs.
-- opts.inputs is a list of { name, value, type } tables corresponding to spec:inputs entries.
-- opts.variables is a list of { key, value } tables for GitLab pipeline variables.
-- Inputs and variables are kept separate: inputs map to --input, variables to --variable.
-- Distinct from api.run_pipeline which calls the REST API and returns pipeline JSON.
function M.run_pipeline(opts)
  opts = opts or {}

  if not opts.ref or opts.ref == "" then
    return nil, "ref is required"
  end

  local args = { "ci", "run", "-b", opts.ref }

  if opts.project and opts.project ~= "" then
    vim.list_extend(args, { "--repo", opts.project })
  end

  for _, input in ipairs(opts.inputs or {}) do
    local formatted, err = format_input(input)
    if not formatted then
      return nil, err
    end
    vim.list_extend(args, { "--input", formatted })
  end

  for _, var in ipairs(opts.variables or {}) do
    if var.key and var.key ~= "" then
      vim.list_extend(args, { "--variable", var.key .. "=" .. tostring(var.value or "") })
    end
  end

  return M.run(args, { cwd = opts.cwd })
end

function M.auth_status(host, opts)
  opts = opts or {}

  local args = {
    "auth",
    "status",
  }

  if host and host ~= "" then
    vim.list_extend(args, {
      "--hostname",
      host,
    })
  end

  return M.run(args, {
    cwd = opts.cwd,
  })
end

function M.auth_login(host, token, opts)
  opts = opts or {}

  if not host or host == "" then
    return nil, "host is required"
  end

  if not token or token == "" then
    return nil, "token is required"
  end

  return M.run({
    "auth",
    "login",
    "--hostname",
    host,
    "--stdin",
  }, {
    cwd = opts.cwd,
    stdin = token .. "\n",
  })
end

return M
