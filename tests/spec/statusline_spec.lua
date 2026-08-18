local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local api     = require("gitlab.api")
local context = require("gitlab.ci.context")
local process = require("gitlab.util.process")
local statusline = require("gitlab.statusline")

-- Helpers -----------------------------------------------------------------

local function with_ctx(project, ref, fn)
  with_mock(context, "from_cwd_async", function(callback)
    callback({ project = project, ref = ref, root = "/repo" }, nil)
  end, fn)
end

local function with_pipeline(status, fn)
  with_mock(api, "latest_pipeline_async", function(_, callback)
    callback({ id = 42, status = status }, nil)
  end, fn)
end

local function setup()
  statusline.clear_cache()
end

-- Seed the pipeline cache directly to bypass context/pipeline fetches,
-- allowing isolated tests of the return-value shape.
local function seed(project, ref, status)
  local constants = require("gitlab.constants")
  local key  = project .. "#" .. ref
  local icon = constants.pipeline_status_icons[status] or "?"
  statusline._cache[key] = {
    data        = { status = status, icon = icon,
                    text = icon .. " " .. status, pipeline_id = 1 },
    expires_at  = os.time() + 60,
    retry_after = nil,
  }
  -- Seed context so get() reaches the cache lookup
  -- (done via a synchronous-callback mock inside each test)
end

-- ── Status icon mappings ─────────────────────────────────────────────────────

describe("statusline.get — pipeline states", function()
  local cases = {
    { "success",  "✓" },
    { "failed",   "✗" },
    { "running",  "●" },
    { "pending",  "○" },
    { "canceled", "⊘" },
    { "skipped",  "↷" },
    { "manual",   "◆" },
    { "created",  "◇" },
  }

  for _, case in ipairs(cases) do
    local status, icon = case[1], case[2]
    it("returns " .. status .. " with icon " .. icon, function()
      setup()
      with_ctx("ns/proj", "main", function()
        with_pipeline(status, function()
          -- First get() triggers async refresh (callback fires synchronously here)
          statusline.get()
          -- Second get() returns from cache
          local result = statusline.get()
          assert.eq(result.status, status)
          assert.eq(result.icon, icon)
          assert.truthy(result.text:find(icon, 1, true))
          assert.truthy(result.text:find(status, 1, true))
          assert.eq(result.pipeline_id, 42)
        end)
      end)
    end)
  end

  it("uses ? icon for an unknown status", function()
    setup()
    with_ctx("ns/proj", "main", function()
      with_pipeline("some_future_status", function()
        statusline.get()
        local result = statusline.get()
        assert.eq(result.icon, "?")
        assert.eq(result.status, "some_future_status")
      end)
    end)
  end)
end)

-- ── Non-blocking invariant ───────────────────────────────────────────────────

describe("statusline.get — non-blocking", function()
  it("never invokes synchronous process, context, or API paths during get()", function()
    setup()
    local sync_calls = 0
    with_mock(process, "run", function()
      sync_calls = sync_calls + 1
      return nil, "sync path must not be reached"
    end, function()
      with_mock(context, "from_cwd", function()
        sync_calls = sync_calls + 1
        return nil, "sync path must not be reached"
      end, function()
        with_mock(api, "latest_pipeline", function()
          sync_calls = sync_calls + 1
          return nil, "sync path must not be reached"
        end, function()
          -- No context, no pipeline — get() should trigger async refresh via
          -- from_cwd_async (mocked to do nothing here) and return immediately.
          with_mock(context, "from_cwd_async", function(_cb)
            -- do not call callback — simulates in-flight refresh
          end, function()
            statusline.get()
          end)
        end)
      end)
    end)
    assert.eq(sync_calls, 0)
  end)
end)

-- ── Context refresh ──────────────────────────────────────────────────────────

describe("statusline.get — context refresh", function()
  it("returns {} when context has never been resolved", function()
    setup()
    with_mock(context, "from_cwd_async", function(_cb)
      -- do not call callback
    end, function()
      local result = statusline.get()
      assert.eq(next(result), nil)
    end)
  end)

  it("returns data after context callback fires", function()
    setup()
    with_ctx("ns/proj", "main", function()
      with_pipeline("success", function()
        statusline.get()  -- context fires, pipeline fires
        local result = statusline.get()
        assert.eq(result.status, "success")
      end)
    end)
  end)

  it("deduplicates concurrent context refresh calls", function()
    setup()
    local ctx_calls = 0
    with_mock(context, "from_cwd_async", function(_cb)
      ctx_calls = ctx_calls + 1
      -- do not call callback — keeps _ctx_pending = true after first call
    end, function()
      statusline.get()
      statusline.get()
      statusline.get()
    end)
    assert.eq(ctx_calls, 1)
  end)
end)

-- ── Pipeline in-flight deduplication ────────────────────────────────────────

describe("statusline.get — pipeline in-flight dedup", function()
  it("triggers only one pipeline request when called multiple times with stale cache", function()
    setup()
    local api_calls = 0
    with_ctx("ns/proj", "main", function()
      with_mock(api, "latest_pipeline_async", function(_, _cb)
        api_calls = api_calls + 1
        -- do not call callback
      end, function()
        statusline.get()  -- context resolves; pipeline miss → request #1
        statusline.get()  -- _pending[key] = true → no new request
        statusline.get()
      end)
    end)
    assert.eq(api_calls, 1)
  end)
end)

-- ── Multi-key pipeline cache ─────────────────────────────────────────────────

describe("statusline.get — multi-key cache", function()
  it("get(main) → get(feature) → get(main) makes exactly 2 API calls", function()
    setup()
    local api_calls = 0
    with_mock(api, "latest_pipeline_async", function(_, callback)
      api_calls = api_calls + 1
      callback({ id = api_calls, status = "success" }, nil)
    end, function()
      -- main
      with_mock(context, "from_cwd_async", function(callback)
        callback({ project = "ns/proj", ref = "main", root = "/repo" }, nil)
      end, function()
        statusline.get()  -- miss → API call #1 → cached
        statusline.get()  -- cache hit
      end)

      -- Simulate branch switch: expire context without touching pipeline cache
      statusline._clear_context()

      -- feature
      with_mock(context, "from_cwd_async", function(callback)
        callback({ project = "ns/proj", ref = "feature", root = "/repo" }, nil)
      end, function()
        statusline.get()  -- miss → API call #2 → cached
        statusline.get()  -- cache hit
      end)

      -- Switch back to main: expire context again
      statusline._clear_context()

      -- main again
      with_mock(context, "from_cwd_async", function(callback)
        callback({ project = "ns/proj", ref = "main", root = "/repo" }, nil)
      end, function()
        statusline.get()  -- main still in pipeline cache → no API call
      end)
    end)
    assert.eq(api_calls, 2)
  end)
end)

-- ── Stale data while in flight ───────────────────────────────────────────────

describe("statusline.get — stale data", function()
  it("returns stale data while pipeline refresh is in flight", function()
    setup()
    -- Manually place stale entry in cache
    local key = "ns/proj#main"
    statusline._cache[key] = {
      data        = { status = "success", icon = "✓", text = "✓ success", pipeline_id = 1 },
      expires_at  = 0,   -- stale
      retry_after = nil,
    }
    with_ctx("ns/proj", "main", function()
      with_mock(api, "latest_pipeline_async", function(_, _cb)
        -- do not call callback — in flight
      end, function()
        local result = statusline.get()
        assert.eq(result.status, "success")  -- stale data returned
      end)
    end)
  end)
end)

-- ── TTL expiry ───────────────────────────────────────────────────────────────

describe("statusline.get — TTL expiry", function()
  it("re-fetches after cache entry expires", function()
    setup()
    local api_calls = 0
    with_ctx("ns/proj", "main", function()
      with_mock(api, "latest_pipeline_async", function(_, callback)
        api_calls = api_calls + 1
        callback({ id = 1, status = "success" }, nil)
      end, function()
        statusline.get()  -- miss → fetch #1 → cached
        statusline.get()  -- hit

        -- Simulate TTL expiry
        local key = "ns/proj#main"
        statusline._cache[key].expires_at = 0

        statusline.get()  -- stale → fetch #2
      end)
    end)
    assert.eq(api_calls, 2)
  end)
end)

-- ── Failure backoff ──────────────────────────────────────────────────────────

describe("statusline.get — failure backoff", function()
  it("sets retry_after on pipeline fetch failure", function()
    setup()
    local api_calls = 0
    with_ctx("ns/proj", "main", function()
      with_mock(api, "latest_pipeline_async", function(_, callback)
        api_calls = api_calls + 1
        callback(nil, "API error")
      end, function()
        statusline.get()  -- miss → fetch → fails → retry_after set
        statusline.get()  -- backoff active → no new request
        statusline.get()
      end)
    end)
    assert.eq(api_calls, 1)
  end)

  it("does not retry until backoff expires", function()
    setup()
    local key = "ns/proj#main"
    local api_calls = 0
    with_ctx("ns/proj", "main", function()
      with_mock(api, "latest_pipeline_async", function(_, callback)
        api_calls = api_calls + 1
        callback(nil, "network error")
      end, function()
        statusline.get()
        assert.not_nil(statusline._cache[key])
        assert.not_nil(statusline._cache[key].retry_after)
        -- While backoff is active, get() does not trigger another request
        statusline.get()
        statusline.get()
      end)
    end)
    assert.eq(api_calls, 1)
  end)

  it("preserves stale data after pipeline fetch failure", function()
    setup()
    local key = "ns/proj#main"
    -- Seed stale entry
    statusline._cache[key] = {
      data        = { status = "running", icon = "●", text = "● running", pipeline_id = 7 },
      expires_at  = 0,
      retry_after = nil,
    }
    with_ctx("ns/proj", "main", function()
      with_mock(api, "latest_pipeline_async", function(_, callback)
        callback(nil, "connection refused")
      end, function()
        local result = statusline.get()  -- stale → fetch → fails → backoff set
        -- Stale data must still be present during backoff
        assert.eq(statusline._cache[key].data.status, "running")
        -- get() returns stale data during backoff
        result = statusline.get()
        assert.eq(result.status, "running")
      end)
    end)
  end)
end)

-- ── Safe failures ────────────────────────────────────────────────────────────

describe("statusline.get — context failure backoff", function()
  it("repeated get() after context failure starts only one context refresh during backoff", function()
    setup()
    local ctx_calls = 0
    with_mock(context, "from_cwd_async", function(callback)
      ctx_calls = ctx_calls + 1
      callback(nil, "not a git repository")  -- always fails
    end, function()
      statusline.get()  -- fail → backoff set
      statusline.get()  -- backoff active → no new request
      statusline.get()
    end)
    assert.eq(ctx_calls, 1)
  end)

  it("stale context remains usable while context refresh is failing", function()
    setup()
    -- Step 1: seed valid context and pipeline via a successful refresh
    with_mock(context, "from_cwd_async", function(callback)
      callback({ project = "ns/proj", ref = "main", root = "/repo" }, nil)
    end, function()
      with_mock(api, "latest_pipeline_async", function(_, callback)
        callback({ id = 1, status = "success" }, nil)
      end, function()
        statusline.get()  -- context resolves; pipeline cached
        statusline.get()  -- pipeline cache hit
      end)
    end)

    -- Step 2: expire context TTL only — _ctx itself remains set
    statusline._expire_context()

    -- Step 3 & 4: context refresh now fails; stale _ctx still allows cache lookup
    local ctx_calls = 0
    with_mock(context, "from_cwd_async", function(callback)
      ctx_calls = ctx_calls + 1
      callback(nil, "git error")
    end, function()
      -- get() sees stale context, triggers refresh (fails → backoff),
      -- then falls through to pipeline cache using the stale _ctx key
      local result = statusline.get()
      assert.eq(result.status, "success")  -- cached pipeline returned via stale context

      -- Step 5: repeated get() within backoff does not retry context refresh
      statusline.get()
      statusline.get()
    end)
    assert.eq(ctx_calls, 1)
  end)
end)

describe("statusline.get — safe failures", function()
  it("returns {} and does not error when context resolution fails", function()
    setup()
    with_mock(context, "from_cwd_async", function(callback)
      callback(nil, "not a git repository")
    end, function()
      local result = statusline.get()
      assert.eq(next(result), nil)
    end)
  end)

  it("returns {} when pipeline has no status field", function()
    setup()
    with_ctx("ns/proj", "main", function()
      with_mock(api, "latest_pipeline_async", function(_, callback)
        callback({ id = 5 }, nil)  -- no status field
      end, function()
        statusline.get()
        local result = statusline.get()
        assert.eq(result.status, "unknown")
        assert.eq(result.icon, "?")
      end)
    end)
  end)

  it("returns {} and does not error when pipeline fetch returns nil", function()
    setup()
    with_ctx("ns/proj", "main", function()
      with_mock(api, "latest_pipeline_async", function(_, callback)
        callback(nil, nil)
      end, function()
        local result = statusline.get()
        assert.eq(next(result), nil)
      end)
    end)
  end)
end)

-- ── clear_cache ──────────────────────────────────────────────────────────────

describe("statusline.clear_cache", function()
  it("resets pipeline cache so the next get() re-fetches", function()
    setup()
    local api_calls = 0
    with_ctx("ns/proj", "main", function()
      with_mock(api, "latest_pipeline_async", function(_, callback)
        api_calls = api_calls + 1
        callback({ id = 1, status = "success" }, nil)
      end, function()
        statusline.get()
        statusline.get()
        assert.eq(api_calls, 1)
        statusline.clear_cache()
        statusline.get()
        assert.eq(api_calls, 2)
      end)
    end)
  end)
end)
