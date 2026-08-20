local git = require("gitlab.git")
local glab = require("gitlab.glab")
local notification = require("gitlab.ui.notification")
local log_buffer = require("gitlab.ci.log_buffer")

local M = {}

local function strip_ansi(line)
  line = line:gsub("\27%[[0-9;?]*[ -/]*[@-~]", "")
  line = line:gsub("\27%][^\7]*\7", "")
  return line
end

local function strip_gitlab_prefix(line)
  -- 2026-06-11T20:13:01.614647Z 00O something
  line = line:gsub("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z%s+%d%d[OE]%s?", "")
  return line
end

local function clean_section_marker(line)
  line = line:gsub("^section_start:%d+:[%w_%-]+%s*", "")
  line = line:gsub("^section_end:%d+:[%w_%-]+%s*", "")
  return line
end

local function clean_log_line(line)
  line = strip_ansi(line)
  line = strip_gitlab_prefix(line)
  line = clean_section_marker(line)
  line = line:gsub("^%+%s*", "")
  return vim.trim(line)
end

local function clean_logs(output)
  local cleaned = {}

  for _, line in ipairs(vim.split(output, "\n", { plain = true })) do
    local clean = clean_log_line(line)

    if clean ~= "" then
      table.insert(cleaned, clean)
    end
  end

  return cleaned
end

local function repo_root()
  local root, err = git.root()
  if not root then
    notification.error(err)
    return nil
  end

  return root
end

local function show_logs(root, job_id, project)
  local args = {
    "ci",
    "trace",
    tostring(job_id),
  }
  if project and project ~= "" then
    vim.list_extend(args, { "--repo", project })
  end
  local output, err = glab.run(args, {
    cwd = root,
  })

  if err then
    notification.error(err)
    return
  end

  local lines = clean_logs(output)

  log_buffer.open(job_id, lines)
end

function M.logs(opts)
  local root = (opts and opts.root) or repo_root()
  if not root then
    return
  end

  local job_id = opts and opts.args or ""
  if job_id == "" then
    notification.error("job_id is required")
    return
  end

  show_logs(root, job_id, opts and opts.project)
end

return M
