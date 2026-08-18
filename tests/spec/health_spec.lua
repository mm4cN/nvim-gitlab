local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert

local auth = require("gitlab.auth")
local config = require("gitlab.config")
local git = require("gitlab.git")
local health = require("gitlab.health")

describe("dependency health checks", function()
  it("reports required NUI, configured Telescope fallback, and optional token", function()
    local messages = { error = {}, info = {}, warn = {} }
    local health_api = vim.health
    local old_health = {
      start = health_api.start,
      ok = health_api.ok,
      warn = health_api.warn,
      error = health_api.error,
      info = health_api.info,
    }
    local old_picker = config.options.picker
    local old_token = auth.token
    local old_root = git.root
    local modules = { "nui.input", "gitlab.ui.pickers.telescope" }
    local old_loaded = {}
    local old_preload = {}

    for _, name in ipairs(modules) do
      old_loaded[name] = package.loaded[name]
      old_preload[name] = package.preload[name]
      package.loaded[name] = nil
      package.preload[name] = function()
        error(name .. " unavailable")
      end
    end

    health_api.start = function() end
    health_api.ok = function() end
    health_api.warn = function(message) table.insert(messages.warn, message) end
    health_api.error = function(message) table.insert(messages.error, message) end
    health_api.info = function(message) table.insert(messages.info, message) end
    config.options.picker = "telescope"
    auth.token = function() return nil, "GITLAB_TOKEN is not set" end
    git.root = function() return nil, "not in repository" end

    local ok, err = pcall(function()
      health.check()
      assert.contains(table.concat(messages.error, "\n"), "nui.nvim not found (required)")
      assert.contains(table.concat(messages.warn, "\n"), "using vim.ui fallback")
      assert.contains(table.concat(messages.info, "\n"), "optional; only required by :GitlabAuth")
    end)

    for name, fn in pairs(old_health) do health_api[name] = fn end
    config.options.picker = old_picker
    auth.token = old_token
    git.root = old_root
    for _, name in ipairs(modules) do
      package.loaded[name] = old_loaded[name]
      package.preload[name] = old_preload[name]
    end

    if not ok then
      error(err)
    end
  end)
end)
