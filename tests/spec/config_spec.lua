local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert

local config = require("gitlab.config")
local picker = require("gitlab.ui.picker")

describe("configuration", function()
  it("exposes only the documented defaults", function()
    local expected = {
      artifacts_dir = "gitlab-artifacts",
      ci_file = ".gitlab-ci.yml",
      extract_artifacts = true,
      gitlab_token_env = "GITLAB_TOKEN",
      glab_binary = "glab",
      picker = "vim_ui",
      scratch_height = 15,
    }
    local count = 0
    for name, value in pairs(config.options) do
      count = count + 1
      assert.eq(value, expected[name])
    end
    assert.eq(count, 7)
    for name, value in pairs(expected) do
      assert.eq(config.options[name], value)
    end
  end)
end)

describe("picker fallback", function()
  it("falls back to vim_ui when Telescope cannot load", function()
    local telescope_name = "gitlab.ui.pickers.telescope"
    local vim_ui_name = "gitlab.ui.pickers.vim_ui"
    local old_picker = config.options.picker
    local old_telescope_loaded = package.loaded[telescope_name]
    local old_telescope_preload = package.preload[telescope_name]
    local old_vim_ui_loaded = package.loaded[vim_ui_name]
    local selected = false

    config.options.picker = "telescope"
    package.loaded[telescope_name] = nil
    package.preload[telescope_name] = function()
      error("Telescope unavailable")
    end
    package.loaded[vim_ui_name] = {
      select = function()
        selected = true
      end,
    }

    local ok, err = pcall(function()
      picker.select({}, {}, function() end)
      assert.eq(selected, true)
    end)

    config.options.picker = old_picker
    package.loaded[telescope_name] = old_telescope_loaded
    package.preload[telescope_name] = old_telescope_preload
    package.loaded[vim_ui_name] = old_vim_ui_loaded

    if not ok then
      error(err)
    end
  end)
end)

describe("picker routing", function()
  for _, backend_name in ipairs({ "vim_ui", "telescope" }) do
    it("routes select to " .. backend_name, function()
      local module_name = "gitlab.ui.pickers." .. backend_name
      local old_picker = config.options.picker
      local old_loaded = package.loaded[module_name]
      local called = false

      config.options.picker = backend_name
      package.loaded[module_name] = {
        select = function()
          called = true
        end,
      }

      local ok, err = pcall(function()
        picker.select({}, {}, function() end)
        assert.eq(called, true)
      end)

      config.options.picker = old_picker
      package.loaded[module_name] = old_loaded

      if not ok then
        error(err)
      end
    end)
  end
end)
