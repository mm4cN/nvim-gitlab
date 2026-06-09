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

return M
