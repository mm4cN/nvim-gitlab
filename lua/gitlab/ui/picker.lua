local config = require("gitlab.config")
local notification = require("gitlab.ui.notification")

local M = {}

local backends = {
  vim_ui = "gitlab.ui.pickers.vim_ui",
}

local function backend_name()
  return config.options.picker or "vim_ui"
end

local function load_backend()
  local name = backend_name()
  local module = backends[name]

  if not module then
    notification.warn("Unknown picker backend: " .. tostring(name) .. ", falling back to vim_ui")
    module = backends.vim_ui
  end

  local ok, backend = pcall(require, module)
  if not ok then
    notification.warn("Failed to load picker backend: " .. tostring(name) .. ", falling back to vim_ui")
    return require(backends.vim_ui)
  end

  return backend
end

function M.select(items, opts, callback)
  return load_backend().select(items, opts or {}, callback)
end

return M
