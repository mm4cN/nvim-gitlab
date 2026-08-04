local M = {}

function M.select(items, opts, callback)
  opts = opts or {}

  vim.ui.select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, callback)
end

return M
