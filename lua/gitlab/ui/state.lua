local M = {
  buf = nil,
  win = nil,
  history = {},
  current = nil,
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
  M.current = nil
end

function M.push(view)
  if M.current then
    table.insert(M.history, M.current)
  end

  M.current = view
end

function M.replace(view)
  M.current = view
end

function M.pop()
  local previous = table.remove(M.history)

  if not previous then
    return nil
  end

  M.current = previous
  return previous
end

return M
