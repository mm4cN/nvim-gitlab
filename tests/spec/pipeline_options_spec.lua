local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local api = require("gitlab.api")
local pipeline_runner = require("gitlab.ci.pipeline_runner")

describe("pipeline runner UI sanitization", function()
  it("normalizes CR/LF and tabs and strips trailing whitespace", function()
    assert.eq(
      pipeline_runner._sanitize_ui("first\r\nsecond\rthird\tfourth  \t"),
      "first second third  fourth"
    )
  end)
end)

describe("pipeline runner option fields", function()
  it("uses a menu and keeps semantic option values separate from labels", function()
    local original = "production\nregion\twest  "
    local field = { name = "environment", value = original, options = { "staging", original } }
    local component, _, menu_entry = pipeline_runner._make_field_component(field, "environment")
    assert.eq(component._gitlab_component_kind, "menu")
    assert.not_nil(menu_entry)
    assert.eq(component.options.lines[2].text, "production region  west")
    assert.eq(component.options.lines[2].value, original)
    assert.eq(field.value, original)
    menu_entry.initializing = false
    component.options.on_change(component.options.lines[2])
    assert.eq(field.value, original)
  end)

  it("keeps fields without options as NuiInput", function()
    local field = { name = "version", value = "1.0", options = {} }
    local component, _, menu_entry = pipeline_runner._make_field_component(field, "version")
    assert.eq(component._gitlab_component_kind, "input")
    assert.is_nil(menu_entry)
  end)

  it("rejects invalid defaults or current selections", function()
    local inputs, err = pipeline_runner._collect_inputs({
      { name = "environment", type = "string", value = "invalid", options = { "dev", "prod" } },
    })
    assert.is_nil(inputs)
    assert.contains(err, "select one of the configured options")
  end)

  it("preserves and rejects an invalid discovered default instead of silently replacing it", function()
    with_mock(api, "pipeline_inputs", function()
      return {
        { name = "environment", type = "string", default = "invalid", options = { "dev", "prod" } },
      }, nil, {}
    end, function()
      local state = {
        project = "ns/proj", ref = "main", fields = {},
        yaml_vars = {}, yaml_vars_key = "",
      }
      pipeline_runner._fetch_inputs(state)
      assert.eq(state.fields[1].value, "invalid")
      local inputs, err = pipeline_runner._collect_inputs(state.fields)
      assert.is_nil(inputs)
      assert.contains(err, "select one of the configured options")
    end)
  end)

  it("rejects invalid option state on described variables", function()
    local valid, err = pipeline_runner._validate_option_values({
      { key = "REGION", value = "invalid", options = { "east", "west" } },
    })
    assert.is_nil(valid)
    assert.contains(err, "'REGION'")
  end)

  it("submits the original unsanitized selected value", function()
    local original = "line one\nline two\r\n"
    local inputs, err = pipeline_runner._collect_inputs({
      { name = "notes", type = "string", value = original, options = { original, "other" } },
    })
    assert.is_nil(err)
    assert.eq(inputs[1].value, original)
  end)
end)

describe("pipeline runner mixed focus navigation", function()
  it("maps Tab and Shift-Tab in both modes for inputs and menus", function()
    local function fake(kind)
      local component = { _gitlab_component_kind = kind, mappings = {} }
      function component:map(mode, key)
        self.mappings[mode .. key] = true
      end
      return component
    end

    local input = fake("input")
    local menu = fake("menu")
    pipeline_runner._configure_tab_navigation({ input, menu })
    for _, component in ipairs({ input, menu }) do
      assert.eq(component.mappings["i<Tab>"], true)
      assert.eq(component.mappings["n<Tab>"], true)
      assert.eq(component.mappings["i<S-Tab>"], true)
      assert.eq(component.mappings["n<S-Tab>"], true)
    end
  end)
end)

describe("pipeline runner ref picker lifecycle", function()
  it("hides the runner, applies selection, refreshes, and restores Ref focus", function()
    local state = { ref = "main" }
    local events = {}
    pipeline_runner._open_ref_picker(
      state,
      { "main", "feature" },
      function() table.insert(events, "close") end,
      function(received)
        assert.eq(received, state)
        table.insert(events, "fetch:" .. received.ref)
      end,
      function(opts)
        assert.eq(opts.focus_ref, true)
        table.insert(events, "build")
      end,
      function(_, _, callback)
        table.insert(events, "picker")
        callback("feature")
      end
    )
    assert.eq(state.ref, "feature")
    assert.eq(table.concat(events, ","), "close,picker,fetch:feature,build")
  end)

  it("restores the previous ref and Ref focus when cancelled", function()
    local state = { ref = "main" }
    local fetched = false
    local focused = false
    pipeline_runner._open_ref_picker(
      state,
      { "main", "feature" },
      function() end,
      function() fetched = true end,
      function(opts) focused = opts.focus_ref end,
      function(_, _, callback) callback(nil) end
    )
    assert.eq(state.ref, "main")
    assert.eq(fetched, false)
    assert.eq(focused, true)
  end)

  it("handles picker completion exactly once", function()
    local state = { ref = "main" }
    local fetched = 0
    local rebuilt = 0
    pipeline_runner._open_ref_picker(
      state,
      { "main", "feature" },
      function() end,
      function() fetched = fetched + 1 end,
      function() rebuilt = rebuilt + 1 end,
      function(_, _, callback)
        callback("feature")
        callback(nil)
      end
    )
    assert.eq(state.ref, "feature")
    assert.eq(fetched, 1)
    assert.eq(rebuilt, 1)
  end)
end)

describe("pipeline runner hints", function()
  it("renders concise vertical keybindings", function()
    local lines = pipeline_runner._runner_hint_lines()
    assert.eq(#lines, 10)
    assert.contains(lines[1] .. lines[2], "<Tab>")
    local text = table.concat(lines, "\n")
    assert.eq(text:find("Refresh", 1, true), nil)
    assert.contains(text, "Remove added variable")
    for _, line in ipairs(lines) do
      if line:find("Refresh", 1, true) then
        assert.eq(line:find("Run", 1, true), nil)
      end
    end
  end)
end)

describe("pipeline runner added variables", function()
  it("focuses the variable now occupying a removed middle index", function()
    local state = {
      variables = {
        { key = "KEEP", value = "one" },
        { key = "REMOVE", value = "two" },
        { key = "NEXT", value = "three" },
      },
      yaml_vars = { { key = "DISCOVERED", value = "yaml" } },
      project_vars = { { key = "PROJECT", value = "api" } },
    }

    local removed, focus_opts = pipeline_runner._remove_added_variable(state, 2)
    assert.eq(removed, true)
    assert.eq(focus_opts.focus_variable_index, 2)
    assert.eq(#state.variables, 2)
    assert.eq(state.variables[1].key, "KEEP")
    assert.eq(state.variables[2].key, "NEXT")
    assert.eq(state.yaml_vars[1].key, "DISCOVERED")
    assert.eq(state.project_vars[1].key, "PROJECT")
  end)

  it("focuses the previous variable after removing the last one", function()
    local state = {
      variables = {
        { key = "PREVIOUS", value = "one" },
        { key = "LAST", value = "two" },
      },
    }
    local removed, focus_opts = pipeline_runner._remove_added_variable(state, 2)
    assert.eq(removed, true)
    assert.eq(focus_opts.focus_variable_index, 1)
    assert.eq(state.variables[1].key, "PREVIOUS")
  end)

  it("returns an explicit Ref fallback after removing the only variable", function()
    local state = { variables = { { key = "ONLY", value = "one" } } }
    local removed, focus_opts = pipeline_runner._remove_added_variable(state, 1)
    assert.eq(removed, true)
    assert.eq(focus_opts.focus_ref, true)
    assert.is_nil(focus_opts.focus_variable_index)
    assert.eq(#state.variables, 0)
  end)

  it("ignores an invalid added-variable index", function()
    local state = { variables = { { key = "KEEP", value = "one" } } }
    assert.eq(pipeline_runner._remove_added_variable(state, 2), false)
    assert.eq(#state.variables, 1)
  end)
end)

describe("pipeline runner submission lifecycle", function()
  local function valid_state()
    return {
      project = "ns/project",
      ref = "main",
      root = "/repo",
      fields = {},
      yaml_vars = {},
      project_vars = {},
      variables = {},
    }
  end

  it("closes before the running notification and pipeline trigger", function()
    local events = {}
    local result = pipeline_runner._submit_pipeline(
      valid_state(),
      function() table.insert(events, "close") end,
      {
        info = function(message) table.insert(events, "info:" .. message) end,
        error = function(message) table.insert(events, "error:" .. message) end,
      },
      function()
        table.insert(events, "trigger")
        return {}, nil
      end
    )
    assert.eq(result, true)
    assert.eq(events[1], "close")
    assert.contains(events[2], "Running pipeline")
    assert.eq(events[3], "trigger")
  end)

  it("leaves the runner open on validation failure", function()
    local state = valid_state()
    state.ref = ""
    local closed = false
    local triggered = false
    local result = pipeline_runner._submit_pipeline(
      state,
      function() closed = true end,
      { info = function() end, error = function() end },
      function()
        triggered = true
        return {}, nil
      end
    )
    assert.eq(result, false)
    assert.eq(closed, false)
    assert.eq(triggered, false)
  end)
end)
