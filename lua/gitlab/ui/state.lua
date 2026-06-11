local M = {
  buf = nil,
  win = nil,
  history = {},
}

function M.is_valid()
  return M.buf
      and vim.api.nvim_buf_is_valid(M.buf)
      and M.win
      and vim.api.nvim_win_is_valid(M.win)
end

function M.reset()
  M.buf = nil
  M.win = nil
  M.history = {}
end

return M
