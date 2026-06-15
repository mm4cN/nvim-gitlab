local M = {}

function M.select(items, opts, callback)
  vim.ui.select(items, opts or {}, callback)
end

return M
