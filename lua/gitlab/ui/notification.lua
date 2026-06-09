local M = {}

function M.info(message)
  vim.notify(message, vim.log.levels.INFO, {
    title = "gitlab.nvim",
  })
end

function M.warn(message)
  vim.notify(message, vim.log.levels.WARN, {
    title = "gitlab.nvim",
  })
end

function M.error(message)
  vim.notify(message, vim.log.levels.ERROR, {
    title = "gitlab.nvim",
  })
end

return M
