local M = {}

function M.info(message)
  vim.notify(message, vim.log.levels.INFO, {
    title = "nvim-gitlab",
  })
end

function M.warn(message)
  vim.notify(message, vim.log.levels.WARN, {
    title = "nvim-gitlab",
  })
end

function M.error(message)
  vim.notify(message, vim.log.levels.ERROR, {
    title = "nvim-gitlab",
  })

  vim.api.nvim_echo({
    { tostring(message), "ErrorMsg" },
  }, true, {})
end

return M
