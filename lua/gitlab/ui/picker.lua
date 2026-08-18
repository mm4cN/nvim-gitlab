local config = require("gitlab.config")
local notification = require("gitlab.ui.notification")

local M = {}

local backends = {
  vim_ui = "gitlab.ui.pickers.vim_ui",
  telescope = "gitlab.ui.pickers.telescope",
}

local function backend_name()
  return config.options.picker or "vim_ui"
end

local function load_backend()
  local name = backend_name()
  local module = backends[name]

  if not module then
    notification.warn(
      "Unknown picker backend: "
        .. tostring(name)
        .. ", falling back to vim_ui"
    )

    return require(backends.vim_ui)
  end

  local loaded, backend = pcall(require, module)
  if loaded then
    return backend
  end

  notification.warn(
    "Could not load picker backend "
      .. tostring(name)
      .. ", falling back to vim_ui: "
      .. tostring(backend)
  )

  return require(backends.vim_ui)
end

function M.select(items, opts, callback)
  return load_backend().select(items, opts or {}, callback)
end

function M.show_pipeline(opts)
  return load_backend().show_pipeline(opts)
end

function M.show_jobs(opts)
  return load_backend().show_jobs(opts)
end

function M.show_job(opts)
  return load_backend().show_job(opts)
end

return M
