local config = require("gitlab.config")

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

function M.close_current()
  vim.cmd("close")
end

function M.show(opts)
  opts = opts or {}

  local title = opts.title or "gitlab.nvim"
  local lines = opts.lines or {}

  vim.cmd("botright split")
  vim.cmd("resize " .. tostring(config.options.scratch_height))

  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_name(buf, title)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = opts.filetype or "gitlab"

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  set_keymaps(buf, opts.keymaps)
end

return M
