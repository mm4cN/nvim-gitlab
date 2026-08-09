local M = {}

local function buffer_name(job_id)
  return string.format("gitlab://job/%s/log", tostring(job_id))
end

local function find_buffer(name)
  local buf = vim.fn.bufnr(name)

  if buf ~= -1 and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end

  return nil
end

function M.create_or_update(job_id, lines)
  local name = buffer_name(job_id)
  local buf = find_buffer(name)

  if not buf then
    buf = vim.api.nvim_create_buf(true, false)

    vim.api.nvim_buf_set_name(buf, name)

    vim.bo[buf].buftype = ""
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "log"

    vim.b[buf].gitlab_job_id = tostring(job_id)
  end

  vim.bo[buf].readonly = false
  vim.bo[buf].modifiable = true

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.bo[buf].modified = false

  return buf
end

function M.open(job_id, lines)
  local buf = M.create_or_update(job_id, lines)

  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)

  return buf
end

return M
