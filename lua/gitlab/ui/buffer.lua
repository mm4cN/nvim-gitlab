local config = require("gitlab.config")
local state = require("gitlab.ui.state")

local M = {}

local function set_keymaps(buf, keymaps)
  if not keymaps then
    return
  end

  for lhs, rhs in pairs(keymaps) do
    vim.keymap.set("n", lhs, rhs, {
      buffer = buf,
      silent = true,
      nowait = true,
    })
  end
end

local function clear_keymaps(buf)
  for _, lhs in ipairs({ "q", "<CR>", "l", "<BS>" }) do
    pcall(vim.keymap.del, "n", lhs, { buffer = buf })
  end
end

local function open_window()
  vim.cmd("botright split")
  vim.cmd("resize " .. tostring(config.options.scratch_height))

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_get_current_win()

  vim.api.nvim_win_set_buf(win, buf)

  state.buf = buf
  state.win = win

  return buf, win
end

local function ensure_window()
  if state.is_valid() then
    vim.api.nvim_set_current_win(state.win)
    return state.buf, state.win
  end

  return open_window()
end

function M.close_current()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  else
    vim.cmd("close")
  end

  state.reset()
end

function M.show(opts)
  opts = opts or {}

  local title = opts.title or "gitlab.nvim"
  local lines = opts.lines or {}

  local buf, _ = ensure_window()

  vim.bo[buf].modifiable = true

  vim.api.nvim_buf_set_name(buf, title)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = opts.filetype or "gitlab"

  clear_keymaps(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  set_keymaps(buf, opts.keymaps)

  vim.bo[buf].modifiable = false
end

return M
