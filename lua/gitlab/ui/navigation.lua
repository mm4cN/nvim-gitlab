local M = {}

function M.job_id_under_cursor()
  local line = vim.api.nvim_get_current_line()
  return line:match("#(%d+)")
end

return M
