local config = require("gitlab.config")

local M = {}

local function notify(message, level)
  local handler = config.options.notification and config.options.notification.handler
  handler = handler or vim.notify
  handler(message, level, {
    title = "nvim-gitlab",
  })
end

function M.info(message)
  notify(message, vim.log.levels.INFO)
end

function M.warn(message)
  notify(message, vim.log.levels.WARN)
end

function M.error(message)
  notify(message, vim.log.levels.ERROR)
end

return M
