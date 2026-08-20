local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local api = require("gitlab.api")
local notification = require("gitlab.ui.notification")
local picker = require("gitlab.ui.picker")
local project_picker = require("gitlab.ui.project_picker")

describe("reusable project picker", function()
  it("shows canonical project paths and returns normalized metadata", function()
    local selected
    local picker_opts
    local project = {
      id = 42,
      name = "project",
      path_with_namespace = "group/project",
      default_branch = "main",
      last_activity_at = "2026-08-20",
    }
    with_mock(api, "projects", function(opts)
      assert.eq(opts.cwd, "/repo")
      return { project }, nil
    end, function()
      with_mock(picker, "select", function(items, opts, callback)
        picker_opts = opts
        callback(items[1])
      end, function()
        project_picker.select({ cwd = "/repo" }, function(value) selected = value end)
      end)
    end)
    assert.eq(selected, project)
    assert.eq(picker_opts.format_item(project), "group/project")
    assert.contains(table.concat(picker_opts.preview(project), "\n"), "Default branch  main")
  end)

  it("reports API failure and completes as cancelled", function()
    local message
    local selected = "not-called"
    with_mock(api, "projects", function() return nil, "forbidden" end, function()
      with_mock(notification, "error", function(value) message = value end, function()
        project_picker.select({}, function(value) selected = value end)
      end)
    end)
    assert.contains(message, "forbidden")
    assert.is_nil(selected)
  end)

  it("reports an empty accessible-project set without opening a picker", function()
    local warned
    local opened = false
    with_mock(api, "projects", function() return {}, nil end, function()
      with_mock(notification, "warn", function(value) warned = value end, function()
        with_mock(picker, "select", function() opened = true end, function()
          project_picker.select({}, function() end)
        end)
      end)
    end)
    assert.contains(warned, "No accessible projects")
    assert.eq(opened, false)
  end)

  it("passes cancellation through without side effects", function()
    local selected = "not-called"
    with_mock(api, "projects", function()
      return { { path_with_namespace = "group/project" } }, nil
    end, function()
      with_mock(picker, "select", function(_, _, callback) callback(nil) end, function()
        project_picker.select({}, function(value) selected = value end)
      end)
    end)
    assert.is_nil(selected)
  end)
end)
