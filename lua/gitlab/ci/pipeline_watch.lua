local api = require("gitlab.api")
local notification = require("gitlab.ui.notification")

local M = {}

local TERMINAL_STATES = {
  success = true,
  failed = true,
  canceled = true,
  skipped = true,
}

local POLL_INTERVAL = 7 -- seconds, middle ground of 5-10 recommendation
local MAX_FAILURES = 3

-- Registry: key = "project:pipeline_id", value = watcher state table
local watchers = {}

-- For testing: inject a custom timer constructor and schedule wrapper.
-- Defaults are captured once so _reset_test_overrides() can restore them
-- without depending on vim.loop/vim.schedule_wrap being re-readable later.
local DEFAULT_TIMER_CONSTRUCTOR = function()
  return vim.loop.new_timer()
end
local DEFAULT_SCHEDULE_WRAP = vim.schedule_wrap

local timer_constructor = DEFAULT_TIMER_CONSTRUCTOR
local schedule_wrap = DEFAULT_SCHEDULE_WRAP

function M._set_timer_constructor(ctor)
  timer_constructor = ctor
end

function M._set_schedule_wrap(wrapper)
  schedule_wrap = wrapper
end

-- _reset_test_overrides restores production timer/schedule behavior.
-- Tests must call this in an always-run cleanup (e.g. after with_mock) so
-- overrides never leak into unrelated tests.
function M._reset_test_overrides()
  timer_constructor = DEFAULT_TIMER_CONSTRUCTOR
  schedule_wrap = DEFAULT_SCHEDULE_WRAP
end

-- notification_level maps terminal state to the notification abstraction's
-- function name (gitlab.ui.notification only exposes info/warn/error).
local function notification_fn(status)
  if status == "failed" then
    return notification.error
  elseif status == "canceled" then
    return notification.warn
  else -- success, skipped, and any unrecognized terminal state
    return notification.info
  end
end

-- format_message builds the completion notification message
local function format_message(pipeline, project)
  local project_str = project or "unknown"
  local ref_str = pipeline.ref or "unknown"
  return string.format(
    "GitLab: %s pipeline #%d %s (%s)",
    project_str,
    pipeline.id,
    pipeline.status or "completed",
    ref_str
  )
end

-- registry_key creates a unique key for a watcher
local function registry_key(project, pipeline_id)
  return tostring(project or "") .. ":" .. tostring(pipeline_id)
end

-- cleanup_watcher is the single path for tearing down a watcher: it removes
-- the registry entry and stops/closes its timer exactly once. Safe to call
-- multiple times or with a timer that is already stopping/closed — libuv
-- timer handles guard stop()/close() internally, but we additionally track
-- watcher.closing so a timer callback already in flight will not attempt a
-- second close() on the same handle.
local function cleanup_watcher(key, watcher)
  local removed = false
  if watchers[key] == watcher then
    watchers[key] = nil
    removed = true
  end
  if removed then
    vim.cmd("redrawstatus")
  end
  if watcher.closing then
    return
  end
  watcher.closing = true
  local timer = watcher.timer
  if timer then
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
end

-- poll_pipeline fetches the current pipeline state and processes it
local function poll_pipeline(key, watcher)
  local project = watcher.project
  local pipeline_id = watcher.pipeline_id
  local root = watcher.root

  -- Fetch current pipeline state
  local pipeline, err = api.pipeline(pipeline_id, {
    cwd = root,
    project = project,
  })

  -- A missing pipeline or an unrecognizable status is treated as a polling
  -- failure so it contributes to the bounded failure policy instead of
  -- leaving the watcher alive forever on malformed responses.
  if not err and (not pipeline or type(pipeline.status) ~= "string" or pipeline.status == "") then
    err = "Malformed pipeline response"
    pipeline = nil
  end

  if err then
    watcher.failure_count = watcher.failure_count + 1
    if watcher.failure_count > MAX_FAILURES then
      cleanup_watcher(key, watcher)
      notification.error(
        "Pipeline watcher for " .. project .. " #" .. pipeline_id .. " stopped: " .. err
      )
    end
    return
  end

  -- Reset failure counter on successful, well-formed poll
  watcher.failure_count = 0

  -- Check for terminal state
  if TERMINAL_STATES[pipeline.status] then
    cleanup_watcher(key, watcher)
    local notify = notification_fn(pipeline.status)
    notify(format_message(pipeline, project))
  end
end

-- watch starts watching a pipeline for completion
function M.watch(opts)
  if not opts or not opts.pipeline_id or not opts.project then
    return false
  end

  local pipeline_id = opts.pipeline_id
  local project = opts.project
  local root = opts.root or vim.fn.getcwd()
  local key = registry_key(project, pipeline_id)

  -- Idempotent: if already watching, do nothing
  if watchers[key] then
    return true
  end

  -- Create watcher state
  local watcher = {
    pipeline_id = pipeline_id,
    project = project,
    root = root,
    failure_count = 0,
    closing = false,
  }

  -- Create and start timer
  local timer = timer_constructor()
  if not timer then
    return false
  end

  watcher.timer = timer

  -- Schedule first poll immediately, then repeat at interval
  timer:start(
    0,
    POLL_INTERVAL * 1000,
    schedule_wrap(function()
      -- The registry, not the timer handle, is authoritative: if this
      -- watcher was already removed (stopped, completed, or failed out) by
      -- the time this callback fires, do nothing. cleanup_watcher() already
      -- stopped/closed the timer that scheduled this callback.
      if watchers[key] ~= watcher then
        return
      end
      poll_pipeline(key, watcher)
    end)
  )

  watchers[key] = watcher
  vim.cmd("redrawstatus")
  return true
end

-- stop halts a running watcher
function M.stop(pipeline_id, project)
  local key = registry_key(project, pipeline_id)
  local watcher = watchers[key]
  if not watcher then
    return false
  end
  cleanup_watcher(key, watcher)
  return true
end

-- is_watching checks if a pipeline is currently being watched
function M.is_watching(pipeline_id, project)
  local key = registry_key(project, pipeline_id)
  return watchers[key] ~= nil
end

-- count returns the current registry size for lightweight consumers such as
-- the statusline. The watcher registry remains the single source of truth.
function M.count()
  local count = 0
  for _ in pairs(watchers) do
    count = count + 1
  end
  return count
end

-- stop_all cleans up every active watcher. Used on VimLeavePre so timers
-- are not left running (and do not fire notifications) during shutdown.
function M.stop_all()
  for key, watcher in pairs(watchers) do
    cleanup_watcher(key, watcher)
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("gitlab_pipeline_watch_shutdown", { clear = true }),
  callback = function()
    M.stop_all()
  end,
})

-- For testing: get internal state
function M._watchers()
  return watchers
end

-- For testing: set custom poll interval
function M._set_poll_interval(interval)
  POLL_INTERVAL = interval
end

return M
