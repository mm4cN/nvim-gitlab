local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local api = require("gitlab.api")
local pipeline_runner = require("gitlab.ci.pipeline_runner")
local picker = require("gitlab.ui.picker")
local project_picker = require("gitlab.ui.project_picker")

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

  it("auto-scrolls before focusing the next or previous off-screen field", function()
    local function fake()
      local component = { mappings = {} }
      function component:map(mode, key, handler)
        self.mappings[mode .. key] = handler
      end
      return component
    end

    local components = { fake(), fake(), fake() }
    local ensured = {}
    local navigation = {
      focus_index = 1,
      ensure_visible = function(index) table.insert(ensured, index) end,
    }
    pipeline_runner._configure_tab_navigation(components, navigation)
    components[1].mappings["n<Tab>"]()
    assert.eq(navigation.focus_index, 2)
    assert.eq(ensured[1], 2)
    components[2].mappings["n<S-Tab>"]()
    assert.eq(navigation.focus_index, 1)
    assert.eq(ensured[2], 1)
  end)
end)

describe("pipeline runner bounded viewport", function()
  local function items(count, size)
    local result = {}
    for _ = 1, count do table.insert(result, { size = size }) end
    return result
  end

  it("keeps a fixed outer height while arbitrarily many fields are paged", function()
    local spec = pipeline_runner._runner_layout_spec()
    local fields = items(100, 3)
    local first, last = pipeline_runner._viewport_range(fields, 1, spec.viewport_height)
    assert.eq(spec.viewport_height, pipeline_runner._form_viewport_height)
    assert.eq(spec.height, spec.viewport_height + 2)
    assert.eq(first, 1)
    assert.eq(last < #fields, true)
    assert.eq(spec.legend_focusable, false)
    assert.eq(spec.legend_width < spec.width, true)
    assert.eq(spec.form_border, "rounded")
    assert.eq(spec.legend_border, "rounded")
  end)

  it("brings a focused component into view in either direction", function()
    local fields = items(20, 3)
    local height = 9
    local down = pipeline_runner._viewport_offset_for_focus(fields, 1, height, 10)
    local first, last = pipeline_runner._viewport_range(fields, down, height)
    assert.eq(10 >= first and 10 <= last, true)
    assert.eq(pipeline_runner._viewport_offset_for_focus(fields, down, height, 2), 2)
  end)

  it("renders a proportional scrollbar that follows viewport position", function()
    local fields = items(20, 3)
    local top = pipeline_runner._viewport_scrollbar_lines(fields, 1, 9)
    local middle = pipeline_runner._viewport_scrollbar_lines(fields, 7, 9)
    local bottom = pipeline_runner._viewport_scrollbar_lines(fields, 18, 9)
    assert.eq(#top, 9)
    assert.eq(top[1], "█")
    assert.eq(middle[1], "│")
    assert.eq(bottom[9], "█")
  end)

  it("hides the scrollbar when the whole form fits", function()
    local lines = pipeline_runner._viewport_scrollbar_lines(items(2, 3), 1, 9)
    assert.eq(table.concat(lines, ""), string.rep(" ", 9))
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

describe("pipeline runner project picker lifecycle", function()
  local function state()
    return {
      project = "old/project",
      committed_project = "old/project",
      project_fallback = "old/project",
      ref = "feature/old",
      root = "/repo",
      fields = { { name = "OLD", value = "old" } },
      yaml_vars = { { key = "OLD", value = "old" } },
      yaml_vars_key = "old/project|feature/old",
      variables = { { key = "MANUAL", value = "keep" } },
    }
  end

  it("hides the runner, applies selection, refreshes, and restores Ref focus", function()
    local current = state()
    local events = {}
    pipeline_runner._open_project_picker(
      current,
      function() table.insert(events, "close") end,
      function(opts, callback)
        assert.eq(opts.cwd, "/repo")
        table.insert(events, "picker")
        callback({ path_with_namespace = "new/project", default_branch = "trunk" })
      end,
      function(received) table.insert(events, "fetch:" .. received.project .. "|" .. received.ref) end,
      function(opts)
        assert.eq(opts.focus_ref, true)
        table.insert(events, "build")
      end,
      { error = function(message) error(message) end }
    )
    assert.eq(current.project, "new/project")
    assert.eq(current.committed_project, "new/project")
    assert.eq(current.ref, "trunk")
    assert.eq(current.variables[1].key, "MANUAL")
    assert.eq(table.concat(events, ","), "close,picker,fetch:new/project|trunk,build")
  end)

  it("restores Project/Ref and Project focus when cancelled", function()
    local current = state()
    local focused = false
    pipeline_runner._open_project_picker(
      current,
      function() end,
      function(_, callback) callback(nil) end,
      function() error("discovery must not run") end,
      function(opts) focused = opts.focus_project end,
      { error = function(message) error(message) end }
    )
    assert.eq(current.project, "old/project")
    assert.eq(current.ref, "feature/old")
    assert.eq(focused, true)
  end)

  it("keeps Project focus when selection resolves to the committed canonical project", function()
    local current = state()
    local focused_project = false
    local focused_ref = false
    pipeline_runner._open_project_picker(
      current,
      function() end,
      function(_, callback)
        callback({ path_with_namespace = "old/project", default_branch = "main" })
      end,
      function() error("discovery must not run") end,
      function(opts)
        focused_project = opts.focus_project == true
        focused_ref = opts.focus_ref == true
      end,
      { error = function(message) error(message) end }
    )
    assert.eq(current.ref, "feature/old")
    assert.eq(focused_project, true)
    assert.eq(focused_ref, false)
  end)

  it("handles project picker completion exactly once", function()
    local current = state()
    local rebuilt = 0
    pipeline_runner._open_project_picker(
      current,
      function() end,
      function(_, callback)
        callback({ path_with_namespace = "new/project", default_branch = "main" })
        callback(nil)
      end,
      function() end,
      function() rebuilt = rebuilt + 1 end,
      { error = function(message) error(message) end }
    )
    assert.eq(rebuilt, 1)
    assert.eq(current.project, "new/project")
  end)

  it("restores the runner when a selected project has no default branch", function()
    local current = state()
    local message
    local focused = false
    pipeline_runner._open_project_picker(
      current,
      function() end,
      function(_, callback)
        callback({ path_with_namespace = "empty/project", default_branch = "" })
      end,
      function() error("discovery must not run") end,
      function(opts) focused = opts.focus_project end,
      { error = function(value) message = value end }
    )
    assert.eq(current.project, "old/project")
    assert.eq(current.ref, "feature/old")
    assert.contains(message, "no default branch")
    assert.eq(focused, true)
  end)

  it("preserves all runner state through api.projects selection without a default branch", function()
    local current = state()
    local original_fields = current.fields
    local original_yaml_vars = current.yaml_vars
    local original_variables = current.variables
    local discovery_called = false
    local project_lookup_called = false
    local focused = false
    local message

    with_mock(api, "projects", function()
      return {
        {
          id = 42,
          name = "empty",
          path_with_namespace = "empty/project",
          default_branch = "",
          last_activity_at = "2026-08-20",
        },
      }, nil
    end, function()
      with_mock(api, "project", function()
        project_lookup_called = true
        return nil, "must not be called"
      end, function()
        with_mock(picker, "select", function(items, _, callback) callback(items[1]) end, function()
          pipeline_runner._open_project_picker(
            current,
            function() end,
            project_picker.select,
            function() discovery_called = true end,
            function(opts) focused = opts.focus_project == true end,
            { error = function(value) message = value end }
          )
        end)
      end)
    end)

    assert.eq(project_lookup_called, false)
    assert.eq(discovery_called, false)
    assert.eq(current.project, "old/project")
    assert.eq(current.committed_project, "old/project")
    assert.eq(current.ref, "feature/old")
    assert.eq(current.fields, original_fields)
    assert.eq(current.yaml_vars, original_yaml_vars)
    assert.eq(current.variables, original_variables)
    assert.contains(message, "no default branch")
    assert.eq(focused, true)
  end)

  it("reuses api.projects metadata without a second api.project lookup", function()
    local current = state()
    local project_lookup_called = false
    local discovered
    with_mock(api, "projects", function()
      return {
        {
          id = 42,
          name = "new",
          path_with_namespace = "canonical/new",
          default_branch = "trunk",
        },
      }, nil
    end, function()
      with_mock(api, "project", function()
        project_lookup_called = true
        return nil, "must not be called"
      end, function()
        with_mock(picker, "select", function(items, _, callback) callback(items[1]) end, function()
          pipeline_runner._open_project_picker(
            current,
            function() end,
            project_picker.select,
            function(received) discovered = received.project .. "|" .. received.ref end,
            function(opts) assert.eq(opts.focus_ref, true) end,
            { error = function(message) error(message) end }
          )
        end)
      end)
    end)
    assert.eq(project_lookup_called, false)
    assert.eq(discovered, "canonical/new|trunk")
    assert.eq(current.committed_project, "canonical/new")
  end)
end)

describe("pipeline runner hints", function()
  it("renders concise vertical keybindings", function()
    local lines = pipeline_runner._runner_hint_lines()
    assert.eq(#lines, 14)
    local text = table.concat(lines, "\n")
    assert.contains(text, "Keybindings")
    assert.contains(text, "C-s       Run pipeline")
    assert.contains(text, "C-p       Pick project")
    assert.contains(text, "C-r       Pick ref")
    assert.eq(text:find("<CR>", 1, true), nil)
  end)
end)

describe("pipeline runner component mappings", function()
  local function fake(kind)
    local component = { _gitlab_component_kind = kind, mappings = {} }
    function component:map(mode, key, handler)
      self.mappings[mode .. key] = handler
    end
    return component
  end

  it("maps global Run on Project, Ref, input, and menu without mapping Enter", function()
    local components = { fake("input"), fake("input"), fake("input"), fake("menu") }
    local runs = 0
    pipeline_runner._configure_component_mappings(components, {
      run = function() runs = runs + 1 end,
      add_variable = function() end,
      close = function() end,
    })
    for _, component in ipairs(components) do
      assert.not_nil(component.mappings["i<C-s>"])
      assert.not_nil(component.mappings["n<C-s>"])
      assert.is_nil(component.mappings["i<CR>"])
      assert.is_nil(component.mappings["n<CR>"])
      assert.is_nil(component.mappings["i<PageDown>"])
      assert.is_nil(component.mappings["n<PageUp>"])
    end
    components[1].mappings["i<C-s>"]()
    components[2].mappings["n<C-s>"]()
    assert.eq(runs, 2)
  end)

  it("submits a Project-and-Ref-only pipeline through the global mapping", function()
    local project = fake("input")
    local ref = fake("input")
    local triggered = false
    local state = {
      project = "ns/project", ref = "main", root = "/repo",
      fields = {}, yaml_vars = {}, variables = {},
    }
    local run = function()
      pipeline_runner._submit_pipeline(
        state,
        function() end,
        { info = function() end, error = function() end },
        function() triggered = true return {}, nil end
      )
    end
    pipeline_runner._configure_component_mappings({ project, ref }, {
      run = run, add_variable = function() end, close = function() end,
    })
    project.mappings["i<C-s>"]()
    assert.eq(triggered, true)
  end)

  it("keeps option menus on j/k and arrow selection keys", function()
    local field = { name = "environment", value = "dev", options = { "dev", "prod" } }
    local component = pipeline_runner._make_field_component(field, "environment")
    assert.eq(component.options.keymap.focus_next[1], "j")
    assert.eq(component.options.keymap.focus_next[2], "<Down>")
    assert.eq(component.options.keymap.focus_prev[1], "k")
    assert.eq(component.options.keymap.focus_prev[2], "<Up>")
  end)

  it("maps project picking on every component so it remains available after Ref focus", function()
    local project = fake("input")
    local ref = fake("input")
    local menu = fake("menu")
    local picked = 0
    pipeline_runner._configure_project_picker_mapping({ project, ref, menu }, function() picked = picked + 1 end)
    for _, component in ipairs({ project, ref, menu }) do
      assert.not_nil(component.mappings["i<C-p>"])
      assert.not_nil(component.mappings["n<C-p>"])
    end
    ref.mappings["n<C-p>"]()
    menu.mappings["n<C-p>"]()
    assert.eq(picked, 2)
  end)

  it("intentionally reserves C-r for global Ref picking in insert and normal mode", function()
    local project = fake("input")
    local ref = fake("input")
    local menu = fake("menu")
    local picked = 0
    pipeline_runner._configure_ref_picker_mapping({ project, ref, menu }, function() picked = picked + 1 end)
    for _, component in ipairs({ project, ref, menu }) do
      assert.not_nil(component.mappings["i<C-r>"])
      assert.not_nil(component.mappings["n<C-r>"])
    end
    project.mappings["n<C-r>"]()
    menu.mappings["n<C-r>"]()
    assert.eq(picked, 2)
  end)
end)

describe("pipeline runner unbounded discovery", function()
  it("keeps all discovered spec inputs", function()
    local discovered = {}
    for i = 1, 20 do table.insert(discovered, { name = "field" .. i, default = tostring(i) }) end
    with_mock(api, "pipeline_inputs", function() return discovered, nil, {} end, function()
      local state = { project = "ns/proj", ref = "main", fields = {}, yaml_vars = {}, yaml_vars_key = "" }
      pipeline_runner._fetch_inputs(state)
      assert.eq(#state.fields, 20)
    end)
  end)
end)

describe("pipeline runner project changes", function()
  local function state()
    return {
      project = "new/project",
      committed_project = "old/project",
      ref = "feature/old",
      root = "/repo",
      fields = { { name = "OLD_INPUT", value = "old" } },
      yaml_vars = { { key = "OLD_VAR", value = "old" } },
      yaml_vars_key = "old/project|feature/old",
      variables = { { key = "MANUAL", value = "keep" } },
    }
  end

  it("commits the canonical API project, resets Ref, and refreshes discovery", function()
    local current = state()
    local requested
    local discovered
    local ok, changed = pipeline_runner._change_project(
      current,
      "alias/project",
      function(opts)
        requested = opts
        return {
          path_with_namespace = "canonical/project",
          default_branch = "trunk",
        }, nil
      end,
      function(received)
        discovered = received.project .. "|" .. received.ref
      end
    )
    assert.eq(ok, true)
    assert.eq(changed, true)
    assert.eq(requested.project, "alias/project")
    assert.eq(requested.cwd, "/repo")
    assert.eq(current.project, "canonical/project")
    assert.eq(current.committed_project, "canonical/project")
    assert.eq(current.ref, "trunk")
    assert.eq(#current.fields, 0)
    assert.eq(#current.yaml_vars, 0)
    assert.eq(current.yaml_vars_key, "")
    assert.eq(discovered, "canonical/project|trunk")
    assert.eq(current.variables[1].key, "MANUAL")
    assert.eq(current.variables[1].value, "keep")
  end)

  it("trims submitted Project input before comparison and metadata lookup", function()
    local current = state()
    local requested
    local ok, changed = pipeline_runner._change_project(
      current,
      "  canonical/project\t",
      function(opts)
        requested = opts.project
        return { path_with_namespace = "canonical/project", default_branch = "main" }, nil
      end,
      function() end
    )
    assert.eq(ok, true)
    assert.eq(changed, true)
    assert.eq(requested, "canonical/project")
    assert.eq(current.project, "canonical/project")
  end)

  it("rejects an empty Project after trimming and restores visible values", function()
    local current = state()
    local resolved = false
    local discovered = false
    local ok, err = pipeline_runner._change_project(
      current,
      " \t ",
      function() resolved = true end,
      function() discovered = true end
    )
    assert.is_nil(ok)
    assert.eq(err, "project is required")
    assert.eq(current.project, "old/project")
    assert.eq(current.ref, "feature/old")
    assert.eq(resolved, false)
    assert.eq(discovered, false)
  end)

  it("does not resolve or reset a project submitted again unchanged", function()
    local current = state()
    current.project = "old/project"
    local resolved = false
    local discovered = false
    local ok, changed = pipeline_runner._change_project(
      current,
      current.project,
      function() resolved = true end,
      function() discovered = true end
    )
    assert.eq(ok, true)
    assert.eq(changed, false)
    assert.eq(resolved, false)
    assert.eq(discovered, false)
    assert.eq(current.ref, "feature/old")
  end)

  it("canonicalizes the initial context project without resetting its current Ref", function()
    local current = state()
    current.project = "context/project"
    current.committed_project = nil
    current.project_fallback = "context/project"
    local discovered = false
    local ok, changed = pipeline_runner._change_project(
      current,
      current.project,
      function()
        return { path_with_namespace = "Canonical/Project", default_branch = "main" }, nil
      end,
      function() discovered = true end
    )
    assert.eq(ok, true)
    assert.eq(changed, false)
    assert.eq(current.project, "Canonical/Project")
    assert.eq(current.committed_project, "Canonical/Project")
    assert.eq(current.project_fallback, "Canonical/Project")
    assert.eq(current.ref, "feature/old")
    assert.eq(discovered, false)
  end)

  it("does not reset Ref when an alias resolves to the committed canonical project", function()
    local current = state()
    local discovered = false
    local ok, changed = pipeline_runner._change_project(
      current,
      "project-alias",
      function()
        return { path_with_namespace = "old/project", default_branch = "main" }, nil
      end,
      function() discovered = true end
    )
    assert.eq(ok, true)
    assert.eq(changed, false)
    assert.eq(current.project, "old/project")
    assert.eq(current.committed_project, "old/project")
    assert.eq(current.ref, "feature/old")
    assert.eq(discovered, false)
  end)

  it("restores visible Project and Ref and preserves all state on metadata failure", function()
    local current = state()
    local original_fields = current.fields
    local original_yaml_vars = current.yaml_vars
    local original_variables = current.variables
    local discovered = false
    local ok, err = pipeline_runner._change_project(
      current,
      current.project,
      function() return nil, "404 Project Not Found" end,
      function() discovered = true end
    )
    assert.is_nil(ok)
    assert.eq(err, "404 Project Not Found")
    assert.eq(current.project, "old/project")
    assert.eq(current.committed_project, "old/project")
    assert.eq(current.ref, "feature/old")
    assert.eq(current.fields, original_fields)
    assert.eq(current.yaml_vars, original_yaml_vars)
    assert.eq(current.variables, original_variables)
    assert.eq(discovered, false)
  end)

  it("keeps canonical Project and default Ref committed when discovery fails", function()
    local current = state()
    local manual_variables = current.variables
    local ok, changed = pipeline_runner._change_project(
      current,
      "new/project",
      function()
        return { path_with_namespace = "canonical/project", default_branch = "trunk" }, nil
      end,
      function() return nil, "CI config unavailable" end
    )
    assert.eq(ok, true)
    assert.eq(changed, true)
    assert.eq(current.project, "canonical/project")
    assert.eq(current.committed_project, "canonical/project")
    assert.eq(current.project_fallback, "canonical/project")
    assert.eq(current.ref, "trunk")
    assert.eq(#current.fields, 0)
    assert.eq(#current.yaml_vars, 0)
    assert.eq(current.yaml_vars_key, "")
    assert.eq(current.variables, manual_variables)
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
    }

    local removed, focus_opts = pipeline_runner._remove_added_variable(state, 2)
    assert.eq(removed, true)
    assert.eq(focus_opts.focus_variable_index, 2)
    assert.eq(#state.variables, 2)
    assert.eq(state.variables[1].key, "KEEP")
    assert.eq(state.variables[2].key, "NEXT")
    assert.eq(state.yaml_vars[1].key, "DISCOVERED")
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
