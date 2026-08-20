local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local config = require("gitlab.config")
local notification = require("gitlab.ui.notification")

local function with_handler(handler, fn)
  local original = config.options.notification
  config.options.notification = handler and { handler = handler } or {}
  local ok, err = pcall(fn)
  config.options.notification = original
  if not ok then
    error(err, 0)
  end
end

describe("notification handler", function()
  it("falls back to vim.notify with the default title", function()
    local calls = {}
    with_handler(nil, function()
      with_mock(vim, "notify", function(message, level, opts)
        table.insert(calls, { message = message, level = level, opts = opts })
      end, function()
        notification.info("hello")
      end)
    end)

    assert.eq(#calls, 1)
    assert.eq(calls[1].message, "hello")
    assert.eq(calls[1].level, vim.log.levels.INFO)
    assert.eq(calls[1].opts.title, "nvim-gitlab")
  end)

  it("uses a custom handler instead of vim.notify", function()
    local calls = {}
    with_mock(vim, "notify", function()
      error("vim.notify must not be called")
    end, function()
      with_handler(function(message, level, opts)
        table.insert(calls, { message = message, level = level, opts = opts })
      end, function()
        notification.warn("custom")
      end)
    end)

    assert.eq(#calls, 1)
    assert.eq(calls[1].message, "custom")
    assert.eq(calls[1].level, vim.log.levels.WARN)
    assert.eq(calls[1].opts.title, "nvim-gitlab")
  end)

  it("preserves info, warn, and error level mappings", function()
    local levels = {}
    with_handler(function(_, level)
      table.insert(levels, level)
    end, function()
      notification.info("info")
      notification.warn("warn")
      notification.error("error")
    end)

    assert.eq(levels[1], vim.log.levels.INFO)
    assert.eq(levels[2], vim.log.levels.WARN)
    assert.eq(levels[3], vim.log.levels.ERROR)
  end)
end)
