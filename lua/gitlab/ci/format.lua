local constants = require("gitlab.constants")

local M = {}

function M.datetime(value)
  if not value or value == "" then
    return "unknown"
  end

  local normalized = value
      :gsub("%.%d+Z$", "")
      :gsub("Z$", "")

  local ts = vim.fn.strptime("%Y-%m-%dT%H:%M:%S", normalized)

  if ts <= 0 then
    return value
  end

  return os.date("%Y-%m-%d %H:%M", ts)
end

function M.status_icon(status)
  return constants.pipeline_status_icons[status] or "?"
end

function M.value(value)
  if value == nil or value == "" then
    return "unknown"
  end

  return tostring(value)
end

function M.short_sha(sha)
  if not sha or sha == "" then
    return "unknown"
  end

  return string.sub(sha, 1, 8)
end

function M.duration(seconds)
  if not seconds then
    return "unknown"
  end

  seconds = math.floor(seconds)

  local minutes = math.floor(seconds / 60)
  local rest = seconds % 60

  if minutes > 0 then
    return string.format("%dm%02ds", minutes, rest)
  end

  return tostring(rest) .. "s"
end

function M.job(job)
  return string.format(
    "%s %s [%s] #%s",
    M.status_icon(job.status),
    job.name or "unknown",
    job.status or "unknown",
    tostring(job.id)
  )
end

function M.pipeline(pipeline)
  return string.format(
    "%s #%s %s [%s] %s",
    M.status_icon(pipeline.status),
    tostring(pipeline.id),
    pipeline.ref or "unknown",
    pipeline.status or "unknown",
    M.datetime(pipeline.created_at)
  )
end

return M
