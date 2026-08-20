local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local pipeline_watch = require("gitlab.ci.pipeline_watch")

describe("pipeline watch", function()
  -- Cleanup watchers before each test
  local function clear_watchers()
    pipeline_watch.stop_all()
  end

  it("starts and stops a watcher", function()
    clear_watchers()
    local result = pipeline_watch.watch({
      pipeline_id = 123,
      project = "group/project",
      root = "/tmp",
    })
    assert.truthy(result)
    assert.truthy(pipeline_watch.is_watching(123, "group/project"))

    pipeline_watch.stop(123, "group/project")
    assert.truthy(not pipeline_watch.is_watching(123, "group/project"))
  end)

  it("is idempotent: calling watch twice does not create duplicate watchers", function()
    clear_watchers()
    local watchers = pipeline_watch._watchers()

    pipeline_watch.watch({
      pipeline_id = 123,
      project = "group/project",
      root = "/tmp",
    })
    local count_after_first = 0
    for _ in pairs(watchers) do count_after_first = count_after_first + 1 end

    pipeline_watch.watch({
      pipeline_id = 123,
      project = "group/project",
      root = "/tmp",
    })
    local count_after_second = 0
    for _ in pairs(watchers) do count_after_second = count_after_second + 1 end

    assert.eq(count_after_first, count_after_second)
    assert.eq(count_after_first, 1)

    pipeline_watch.stop(123, "group/project")
  end)

  it("rejects missing pipeline_id or project", function()
    clear_watchers()
    assert.truthy(not pipeline_watch.watch({ project = "group/project" }))
    assert.truthy(not pipeline_watch.watch({ pipeline_id = 123 }))
    assert.truthy(not pipeline_watch.watch({}))
  end)

  it("stop() is safe on non-existent watchers", function()
    clear_watchers()
    local result = pipeline_watch.stop(999, "nonexistent/project")
    -- Should not crash; return value is false for non-existent watcher
    assert.truthy(not result)
  end)

  it("is_watching() returns false for non-existent watcher", function()
    clear_watchers()
    assert.truthy(not pipeline_watch.is_watching(999, "nonexistent/project"))
  end)

  it("uses project + pipeline_id as unique key", function()
    clear_watchers()
    pipeline_watch.watch({ pipeline_id = 123, project = "project/a", root = "/tmp" })
    pipeline_watch.watch({ pipeline_id = 123, project = "project/b", root = "/tmp" })

    assert.truthy(pipeline_watch.is_watching(123, "project/a"))
    assert.truthy(pipeline_watch.is_watching(123, "project/b"))

    pipeline_watch.stop(123, "project/a")
    assert.truthy(not pipeline_watch.is_watching(123, "project/a"))
    assert.truthy(pipeline_watch.is_watching(123, "project/b"))

    pipeline_watch.stop(123, "project/b")
  end)

  it("counts active watchers from the registry", function()
    clear_watchers()
    assert.eq(pipeline_watch.count(), 0)

    pipeline_watch.watch({ pipeline_id = 123, project = "project/a", root = "/tmp" })
    pipeline_watch.watch({ pipeline_id = 123, project = "project/b", root = "/tmp" })
    assert.eq(pipeline_watch.count(), 2)

    pipeline_watch.stop(123, "project/a")
    assert.eq(pipeline_watch.count(), 1)
    pipeline_watch.stop(123, "project/b")
    assert.eq(pipeline_watch.count(), 0)
  end)
end)

describe("pipeline watch polling", function()
  local function clear_watchers()
    pipeline_watch.stop_all()
  end

  -- Create a controllable fake timer for testing. Mirrors the subset of the
  -- libuv timer handle API pipeline_watch relies on, including is_closing()
  -- so cleanup_watcher()'s idempotency guard can be exercised.
  local function make_fake_timer()
    local callback = nil
    local running = false
    local timer = {
      stopped = false,
      closed = false,
    }
    function timer:start(initial, interval, cb)
      callback = cb
      running = true
    end
    function timer:stop()
      self.stopped = true
      running = false
    end
    function timer:close()
      self.closed = true
    end
    function timer:is_closing()
      return self.closed
    end
    function timer:fire()
      if running and callback then
        callback()
      end
    end
    return timer
  end

  -- For testing: inject a schedule_wrap that calls immediately (synchronous testing)
  local function setup_test_env()
    pipeline_watch._set_schedule_wrap(function(fn)
      return fn
    end)
  end

  -- Always restores production timer/schedule behavior via the module's own
  -- reset, so overrides from one test can never leak into the next.
  local function teardown_test_env()
    pipeline_watch._reset_test_overrides()
  end

  -- with_test_env runs fn with synchronous scheduling active and guarantees
  -- teardown_test_env() runs even if fn errors, so a failing assertion in one
  -- test can never leak overrides into the next (matches with_mock's pattern).
  local function with_test_env(fn)
    setup_test_env()
    local ok, err = pcall(fn)
    teardown_test_env()
    if not ok then
      error(err, 0)
    end
  end

  -- Mocks the gitlab.ui.notification abstraction (info/warn/error) instead of
  -- vim.notify directly, matching what pipeline_watch.lua actually calls.
  local function with_notification_spy(fn)
    local notification = require("gitlab.ui.notification")
    local calls = {}
    local function record(level)
      return function(message)
        table.insert(calls, { level = level, message = message })
      end
    end
    with_mock(notification, "info", record("info"), function()
      with_mock(notification, "warn", record("warn"), function()
        with_mock(notification, "error", record("error"), function()
          fn(calls)
        end)
      end)
    end)
  end

  it("detects terminal state and emits one completion notification", function()
    clear_watchers()
    with_test_env(function()
      with_notification_spy(function(calls)
        local fake_timer = make_fake_timer()
        pipeline_watch._set_timer_constructor(function()
          return fake_timer
        end)

        local api = require("gitlab.api")
        with_mock(api, "pipeline", function(pipeline_id, opts)
          return { id = pipeline_id, status = "success", ref = "main" }, nil
        end, function()
          pipeline_watch.watch({
            pipeline_id = 123,
            project = "group/project",
            root = "/tmp",
          })

          fake_timer:fire()

          -- The watcher has been stopped after detecting terminal state
          assert.truthy(not pipeline_watch.is_watching(123, "group/project"))

          -- Should have one notification about success, routed through
          -- notification.info (success -> INFO per the ADR).
          assert.eq(#calls, 1)
          assert.eq(calls[1].level, "info")
          assert.contains(calls[1].message, "success")
        end)
      end)
    end)
  end)

  it("emits appropriate notification level for each terminal state", function()
    local test_cases = {
      { state = "success", expected_level = "info" },
      { state = "failed", expected_level = "error" },
      { state = "canceled", expected_level = "warn" },
      { state = "skipped", expected_level = "info" },
    }

    for _, tc in ipairs(test_cases) do
      clear_watchers()
      with_test_env(function()
        with_notification_spy(function(calls)
          local fake_timer = make_fake_timer()
          pipeline_watch._set_timer_constructor(function()
            return fake_timer
          end)

          local api = require("gitlab.api")
          with_mock(api, "pipeline", function(pipeline_id, opts)
            return { id = pipeline_id, status = tc.state, ref = "main" }, nil
          end, function()
            pipeline_watch.watch({
              pipeline_id = 123,
              project = "group/project",
              root = "/tmp",
            })

            fake_timer:fire()

            assert.eq(#calls, 1)
            assert.eq(calls[1].level, tc.expected_level)
          end)
        end)
      end)
    end
  end)

  it("tolerates transient API failures up to max_failures", function()
    clear_watchers()
    with_test_env(function()
      with_notification_spy(function(calls)
        local fake_timer = make_fake_timer()
        pipeline_watch._set_timer_constructor(function()
          return fake_timer
        end)

        local api = require("gitlab.api")
        local failure_count = { count = 0 }
        with_mock(api, "pipeline", function(pipeline_id, opts)
          failure_count.count = failure_count.count + 1
          if failure_count.count <= 4 then
            return nil, "Temporary error"
          else
            return { id = pipeline_id, status = "success", ref = "main" }, nil
          end
        end, function()
          pipeline_watch.watch({
            pipeline_id = 123,
            project = "group/project",
            root = "/tmp",
          })

          -- Fire timer 4 times: 3 tolerated failures + 1 that triggers stop
          fake_timer:fire()
          fake_timer:fire()
          fake_timer:fire()
          fake_timer:fire()

          -- After max_failures + 1 failures, watcher should be stopped and
          -- exactly one error notification emitted.
          assert.truthy(not pipeline_watch.is_watching(123, "group/project"))
          assert.eq(#calls, 1)
          assert.eq(calls[1].level, "error")
          assert.contains(calls[1].message, "stopped")
        end)
      end)
    end)
  end)

  it("resets failure counter after successful poll", function()
    clear_watchers()
    with_test_env(function()
      local fake_timer = make_fake_timer()
      pipeline_watch._set_timer_constructor(function()
        return fake_timer
      end)

      local api = require("gitlab.api")
      local poll_count = { count = 0 }

      with_mock(api, "pipeline", function(pipeline_id, opts)
        poll_count.count = poll_count.count + 1
        if poll_count.count == 1 then
          return nil, "Error 1"
        elseif poll_count.count == 2 then
          return { id = pipeline_id, status = "running", ref = "main" }, nil
        elseif poll_count.count == 3 then
          return nil, "Error 2"
        elseif poll_count.count == 4 then
          return nil, "Error 3"
        elseif poll_count.count == 5 then
          return nil, "Error 4"
        else
          return { id = pipeline_id, status = "success", ref = "main" }, nil
        end
      end, function()
        pipeline_watch.watch({
          pipeline_id = 123,
          project = "group/project",
          root = "/tmp",
        })

        -- Fire timer to trigger first error
        fake_timer:fire()
        assert.eq(poll_count.count, 1)

        -- Fire again to get successful poll, resetting counter
        fake_timer:fire()
        assert.eq(poll_count.count, 2)

        -- Fire three more times to get 3 consecutive failures
        fake_timer:fire()
        fake_timer:fire()
        fake_timer:fire()
        assert.eq(poll_count.count, 5)

        -- Watcher should still be active after 3 failures (with reset after success)
        assert.truthy(pipeline_watch.is_watching(123, "group/project"))

        -- One more fire should succeed without exceeding max failures
        fake_timer:fire()
        assert.eq(poll_count.count, 6)

        -- Should be stopped now due to success
        assert.truthy(not pipeline_watch.is_watching(123, "group/project"))
      end)
    end)
  end)

  it("treats a malformed successful response as a polling failure", function()
    clear_watchers()
    with_test_env(function()
      with_notification_spy(function(calls)
        local fake_timer = make_fake_timer()
        pipeline_watch._set_timer_constructor(function()
          return fake_timer
        end)

        local api = require("gitlab.api")
        local poll_count = { count = 0 }
        with_mock(api, "pipeline", function(pipeline_id, opts)
          poll_count.count = poll_count.count + 1
          if poll_count.count <= 4 then
            -- No error, but a nil/malformed body — must still count as a failure.
            return nil, nil
          end
          return { id = pipeline_id, status = "success", ref = "main" }, nil
        end, function()
          pipeline_watch.watch({
            pipeline_id = 123,
            project = "group/project",
            root = "/tmp",
          })

          fake_timer:fire()
          fake_timer:fire()
          fake_timer:fire()
          fake_timer:fire()

          -- 4 malformed responses exceed MAX_FAILURES (3): watcher must stop
          -- rather than being left alive indefinitely.
          assert.truthy(not pipeline_watch.is_watching(123, "group/project"))
          assert.eq(#calls, 1)
          assert.eq(calls[1].level, "error")
        end)
      end)
    end)
  end)

  it("treats a response missing a status field as a polling failure", function()
    clear_watchers()
    with_test_env(function()
      with_notification_spy(function(calls)
        local fake_timer = make_fake_timer()
        pipeline_watch._set_timer_constructor(function()
          return fake_timer
        end)

        local api = require("gitlab.api")
        local poll_count = { count = 0 }
        with_mock(api, "pipeline", function(pipeline_id, opts)
          poll_count.count = poll_count.count + 1
          if poll_count.count <= 4 then
            return { id = pipeline_id, ref = "main" }, nil -- no status field
          end
          return { id = pipeline_id, status = "success", ref = "main" }, nil
        end, function()
          pipeline_watch.watch({
            pipeline_id = 123,
            project = "group/project",
            root = "/tmp",
          })

          fake_timer:fire()
          fake_timer:fire()
          fake_timer:fire()
          fake_timer:fire()

          assert.truthy(not pipeline_watch.is_watching(123, "group/project"))
          assert.eq(#calls, 1)
          assert.eq(calls[1].level, "error")
        end)
      end)
    end)
  end)

  it("formats completion notification message correctly", function()
    clear_watchers()
    with_test_env(function()
      with_notification_spy(function(calls)
        local fake_timer = make_fake_timer()
        pipeline_watch._set_timer_constructor(function()
          return fake_timer
        end)

        local api = require("gitlab.api")
        with_mock(api, "pipeline", function(pipeline_id, opts)
          return { id = 12345, status = "failed", ref = "develop" }, nil
        end, function()
          pipeline_watch.watch({
            pipeline_id = 12345,
            project = "mygroup/myproject",
            root = "/tmp",
          })

          fake_timer:fire()

          assert.eq(#calls, 1)
          assert.contains(calls[1].message, "mygroup/myproject")
          assert.contains(calls[1].message, "12345")
          assert.contains(calls[1].message, "failed")
          assert.contains(calls[1].message, "develop")
        end)
      end)
    end)
  end)

  it("cleanup is idempotent: a callback that fires after stop() does not double-close the timer", function()
    clear_watchers()
    with_test_env(function()
      local fake_timer = make_fake_timer()
      pipeline_watch._set_timer_constructor(function()
        return fake_timer
      end)

      local api = require("gitlab.api")
      with_mock(api, "pipeline", function(pipeline_id, opts)
        return { id = pipeline_id, status = "running", ref = "main" }, nil
      end, function()
        pipeline_watch.watch({
          pipeline_id = 123,
          project = "group/project",
          root = "/tmp",
        })

        -- stop() closes the timer synchronously.
        pipeline_watch.stop(123, "group/project")
        assert.truthy(fake_timer.closed)

        -- A callback already scheduled before stop() (e.g. queued on the
        -- event loop) must not attempt to close the timer a second time —
        -- the callback checks the registry (now empty) and returns early.
        fake_timer:fire()
      end)
    end)
    -- No error raised means cleanup_watcher()'s guard held.
  end)

  it("stop_all() cleans up every active watcher without notifying", function()
    clear_watchers()
    with_test_env(function()
      with_notification_spy(function(calls)
        local fake_timer_a = make_fake_timer()
        local fake_timer_b = make_fake_timer()
        local timers = { fake_timer_a, fake_timer_b }
        local next_timer = 0
        pipeline_watch._set_timer_constructor(function()
          next_timer = next_timer + 1
          return timers[next_timer]
        end)

        local api = require("gitlab.api")
        with_mock(api, "pipeline", function(pipeline_id, opts)
          return { id = pipeline_id, status = "running", ref = "main" }, nil
        end, function()
          pipeline_watch.watch({ pipeline_id = 1, project = "group/project", root = "/tmp" })
          pipeline_watch.watch({ pipeline_id = 2, project = "group/project", root = "/tmp" })

          pipeline_watch.stop_all()

          assert.truthy(not pipeline_watch.is_watching(1, "group/project"))
          assert.truthy(not pipeline_watch.is_watching(2, "group/project"))
          assert.truthy(fake_timer_a.closed)
          assert.truthy(fake_timer_b.closed)
          assert.eq(#calls, 0)
        end)
      end)
    end)
  end)
end)
