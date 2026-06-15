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
