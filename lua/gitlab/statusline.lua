local api = require("gitlab.api")
local constants = require("gitlab.constants")
local context = require("gitlab.ci.context")

local M = {}

local CACHE_TTL   = 60
local CONTEXT_TTL = 30
local BACKOFF_TTL = 30

local _ctx             = nil    -- last known context: { project, ref, root }
local _ctx_expires     = 0      -- os.time() when _ctx goes stale
local _ctx_pending     = false  -- async context refresh in flight
local _ctx_retry_after = 0      -- do not retry context refresh before this time

local _cache   = {}         -- { [key] = { data, expires_at, retry_after } }
local _pending = {}         -- { [key] = true }  pipeline refresh in flight

local function trigger_pipeline_refresh(key, ctx)
  _pending[key] = true
  api.latest_pipeline_async({
    project = ctx.project,
    ref     = ctx.ref,
    cwd     = ctx.root,
  }, function(pipeline, err)
    _pending[key] = nil
    if err or not pipeline then
      local e = _cache[key] or {}
      e.retry_after = os.time() + BACKOFF_TTL
      _cache[key] = e
      return
    end
    local status = pipeline.status or "unknown"
    local icon   = constants.pipeline_status_icons[status] or "?"
    _cache[key] = {
      data = {
        status      = status,
        icon        = icon,
        text        = icon .. " " .. status,
        pipeline_id = pipeline.id,
      },
      expires_at  = os.time() + CACHE_TTL,
      retry_after = nil,
    }
    vim.schedule(function()
      vim.cmd("redrawstatus")
    end)
  end)
end

local function trigger_context_refresh()
  _ctx_pending = true
  context.from_cwd_async(function(ctx, err)
    _ctx_pending = false
    if err or not ctx then
      _ctx_retry_after = os.time() + BACKOFF_TTL
      return
    end
    _ctx             = ctx
    _ctx_expires     = os.time() + CONTEXT_TTL
    _ctx_retry_after = 0
    vim.schedule(function()
      vim.cmd("redrawstatus")
    end)
  end)
end

-- get returns statusline-ready pipeline information for the current branch.
-- Always returns immediately — no synchronous process or network I/O.
-- Returns {} while context or pipeline data is unavailable.
-- Caches pipeline results for 60 s per project+ref pair.
-- On failure, backs off for 30 s before retrying to avoid request spam.
function M.get()
  local now = os.time()

  if not _ctx or _ctx_expires <= now then
    if not _ctx_pending and _ctx_retry_after <= now then
      trigger_context_refresh()
    end
    if not _ctx then
      return {}
    end
  end

  local key   = _ctx.project .. "#" .. _ctx.ref
  local entry = _cache[key]

  if entry then
    if entry.retry_after and now < entry.retry_after then
      return entry.data or {}
    end
    if entry.expires_at and now < entry.expires_at then
      return entry.data
    end
  end

  if not _pending[key] then
    trigger_pipeline_refresh(key, _ctx)
  end

  return (entry and entry.data) or {}
end

function M.clear_cache()
  for k in pairs(_cache)   do _cache[k]   = nil end
  for k in pairs(_pending) do _pending[k] = nil end
  _ctx             = nil
  _ctx_expires     = 0
  _ctx_pending     = false
  _ctx_retry_after = 0
end

-- _clear_context resets only context state, leaving pipeline cache intact.
-- Used in tests to simulate a branch switch without discarding pipeline data.
function M._clear_context()
  _ctx             = nil
  _ctx_expires     = 0
  _ctx_pending     = false
  _ctx_retry_after = 0
end

-- _expire_context marks the cached context as stale without clearing it.
-- Used in tests to simulate context TTL expiry while keeping _ctx available
-- as stale data (so get() can still resolve the pipeline cache key).
function M._expire_context()
  _ctx_expires = 0
end

M._cache   = _cache

return M
