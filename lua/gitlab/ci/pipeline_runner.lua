local Input = require("nui.input")
local Layout = require("nui.layout")
local Menu = require("nui.menu")
local Popup = require("nui.popup")

local api = require("gitlab.api")
local context = require("gitlab.ci.context")
local glab = require("gitlab.glab")
local notification = require("gitlab.ui.notification")
local picker = require("gitlab.ui.picker")
local pipeline_watch = require("gitlab.ci.pipeline_watch")
local project_picker = require("gitlab.ui.project_picker")

local M = {}

local FORM_VIEWPORT_HEIGHT = 22
local RUNNER_WIDTH = 94
local LEGEND_WIDTH = 31
local FRAME_HEIGHT = FORM_VIEWPORT_HEIGHT + 2

local function runner_layout_spec()
  return {
    width = RUNNER_WIDTH,
    height = FRAME_HEIGHT,
    viewport_height = FORM_VIEWPORT_HEIGHT,
    legend_width = LEGEND_WIDTH,
    legend_focusable = false,
    form_border = "rounded",
    legend_border = "rounded",
  }
end

local function runner_hint_lines()
  return {
    "  Keybindings",
    "",
    "  Tab       Next field",
    "  S-Tab     Previous field",
    "",
    "  j / k     Choose option",
    "  C-p       Pick project",
    "  C-r       Pick ref",
    "  a         Add variable",
    "  d         Remove variable",
    "",
    "  C-s       Run pipeline",
    "  q / Esc   Close",
    "",
  }
end

local function sanitize_ui(value)
  local text = tostring(value or "")
  text = text:gsub("\r\n", " "):gsub("[\r\n]", " "):gsub("\t", "  ")
  return text:gsub("%s+$", "")
end

local function option_index(options, value)
  for i, option in ipairs(options or {}) do
    if option == value then
      return i
    end
  end
  return nil
end

local function validate_option_values(entries)
  for _, entry in ipairs(entries or {}) do
    if entry.options and #entry.options > 0 and not option_index(entry.options, entry.value) then
      local label = entry.name or entry.key or "field"
      return nil, "Invalid value for '" .. label .. "': select one of the configured options"
    end
  end
  return true, nil
end

local function collect_inputs(fields)
  local valid, err = validate_option_values(fields)
  if not valid then
    return nil, err
  end
  local inputs = {}
  for _, field in ipairs(fields) do
    table.insert(inputs, { name = field.name, value = field.value, type = field.type })
  end
  return inputs, nil
end

-- merge_variables builds the final variable list for the pipeline trigger.
-- Base variables go first; manual variables override matching keys.
-- The result contains no duplicate keys.
local function merge_variables(base_vars, manual_vars)
  local seen = {}
  local result = {}

  for _, pv in ipairs(base_vars) do
    if pv.key and pv.key ~= "" and not seen[pv.key] then
      seen[pv.key] = true
      table.insert(result, { key = pv.key, value = pv.value })
    end
  end

  for _, v in ipairs(manual_vars) do
    if v.key and v.key ~= "" then
      if seen[v.key] then
        for i, r in ipairs(result) do
          if r.key == v.key then
            result[i] = { key = v.key, value = v.value }
            break
          end
        end
      else
        seen[v.key] = true
        table.insert(result, { key = v.key, value = v.value })
      end
    end
  end

  return result
end

local function make_input(label, default, on_change, on_submit)
  return Input({
    border = {
      style = "rounded",
      text = { top = " " .. label .. " ", top_align = "left" },
    },
  }, {
    prompt = "",
    default_value = default or "",
    on_change = on_change,
    on_submit = on_submit or function() end,
  })
end

local function focus(component)
  if component and component.winid and vim.api.nvim_win_is_valid(component.winid) then
    vim.api.nvim_set_current_win(component.winid)
    if component._gitlab_component_kind == "menu" then
      vim.cmd("stopinsert")
    else
      vim.cmd("startinsert!")
    end
  end
end

local function field_label(field)
  return sanitize_ui(field.name)
end

local function make_field_component(field, label)
  if not field.options or #field.options == 0 then
    local input = make_input(label, sanitize_ui(field.value), function(value) field.value = value end)
    input._gitlab_component_kind = "input"
    return input, 3, nil
  end

  local items = {}
  for _, value in ipairs(field.options) do
    table.insert(items, Menu.item(sanitize_ui(value), { value = value }))
  end

  local entry = {
    initializing = true,
    selected_index = option_index(field.options, field.value),
  }
  local height = math.min(#items, 4)
  local menu = Menu({
    border = {
      style = "rounded",
      text = { top = " " .. label .. " ", top_align = "left" },
    },
  }, {
    lines = items,
    max_height = height,
    keymap = {
      focus_next = { "j", "<Down>" },
      focus_prev = { "k", "<Up>" },
      close = {},
      submit = {},
    },
    on_change = function(item)
      if not entry.initializing then
        field.value = item.value
        entry.selected_index = option_index(field.options, item.value)
      end
    end,
  })
  menu._gitlab_component_kind = "menu"
  entry.component = menu
  return menu, height + 2, entry
end

local function configure_tab_navigation(tab_order, navigation)
  navigation = navigation or { focus_index = 1 }

  local function move_to(index)
    navigation.focus_index = index
    if navigation.ensure_visible then
      navigation.ensure_visible(index)
    end
    vim.schedule(function() focus(tab_order[index]) end)
  end

  for _, component in ipairs(tab_order) do
    component:map("i", "<Tab>", function()
      vim.cmd("stopinsert")
      move_to((navigation.focus_index % #tab_order) + 1)
    end, { noremap = true })
    component:map("n", "<Tab>", function()
      move_to((navigation.focus_index % #tab_order) + 1)
    end, { noremap = true })
    component:map("i", "<S-Tab>", function()
      vim.cmd("stopinsert")
      move_to(((navigation.focus_index - 2) % #tab_order) + 1)
    end, { noremap = true })
    component:map("n", "<S-Tab>", function()
      move_to(((navigation.focus_index - 2) % #tab_order) + 1)
    end, { noremap = true })
  end
end

local function viewport_range(items, offset, height)
  offset = math.max(1, math.min(offset or 1, #items))
  local used = 0
  local last = offset - 1
  for i = offset, #items do
    local size = items[i].size
    if used > 0 and used + size > height then
      break
    end
    used = used + math.min(size, height)
    last = i
    if used >= height then
      break
    end
  end
  return offset, last
end

local function viewport_offset_for_focus(items, offset, height, focus_index)
  local first, last = viewport_range(items, offset, height)
  if focus_index >= first and focus_index <= last then
    return first
  end
  if focus_index < first then
    return focus_index
  end

  local new_offset = focus_index
  local used = items[focus_index].size
  while new_offset > 1 and used + items[new_offset - 1].size <= height do
    new_offset = new_offset - 1
    used = used + items[new_offset].size
  end
  return new_offset
end

local function viewport_scrollbar_lines(items, offset, height)
  local lines = {}
  for i = 1, height do
    lines[i] = " "
  end

  local total = 0
  for _, item in ipairs(items) do
    total = total + item.size
  end
  if total <= height then
    return lines
  end

  local first, last = viewport_range(items, offset, height)
  local before = 0
  for i = 1, first - 1 do
    before = before + items[i].size
  end
  local visible = 0
  for i = first, last do
    visible = visible + items[i].size
  end

  local thumb_size = math.max(1, math.floor(height * math.min(visible, height) / total + 0.5))
  local scrollable = math.max(1, total - math.min(visible, height))
  local thumb_start = 1 + math.floor((height - thumb_size) * before / scrollable + 0.5)
  thumb_start = math.min(thumb_start, height - thumb_size + 1)

  for i = 1, height do
    lines[i] = i >= thumb_start and i < thumb_start + thumb_size and "█" or "│"
  end
  return lines
end

local function configure_component_mappings(tab_order, actions)
  for _, component in ipairs(tab_order) do
    component:map("i", "<C-s>", actions.run, { noremap = true })
    component:map("n", "<C-s>", actions.run, { noremap = true })

    component:map("n", "a", actions.add_variable, { noremap = true })
    component:map("i", "<Esc>", function() vim.cmd("stopinsert") end, { noremap = true })
    component:map("n", "q", actions.close, { noremap = true })
    component:map("n", "<Esc>", actions.close, { noremap = true })
  end
end

local function open_ref_picker(state, branches, close_runner, fetch, rebuild, select)
  local previous_ref = state.ref
  local completed = false
  close_runner()
  select(branches, { prompt = "Select ref" }, function(selected)
    if completed then
      return
    end
    completed = true
    if selected then
      state.ref = selected
      fetch(state)
    else
      state.ref = previous_ref
    end
    rebuild({ focus_ref = true })
  end)
end

local function remove_added_variable(state, index)
  if type(index) ~= "number" or index < 1 or index > #state.variables then
    return false
  end
  table.remove(state.variables, index)
  if #state.variables == 0 then
    return true, { focus_ref = true }
  end
  return true, { focus_variable_index = math.min(index, #state.variables) }
end

local function submit_pipeline(state, close_runner, notify, trigger)
  if state.project == "" then
    notify.error("Project is required")
    return false
  end

  if not state.project:match("^[^/]+/[^/]+") then
    notify.error("Project must be in namespace/project format")
    return false
  end

  if state.ref == "" then
    notify.error("Ref is required")
    return false
  end

  local inputs, inputs_err = collect_inputs(state.fields)
  if not inputs then
    notify.error(inputs_err)
    return false
  end
  local yaml_valid, yaml_err = validate_option_values(state.yaml_vars)
  if not yaml_valid then
    notify.error(yaml_err)
    return false
  end
  close_runner()
  notify.info("Running pipeline on " .. state.ref .. " for " .. state.project .. "...")

  local root = state.root or vim.fn.getcwd()

  -- Variable priority: YAML described vars < manual user vars.
  local _, err = trigger({
    project = state.project,
    ref = state.ref,
    inputs = inputs,
    variables = merge_variables(state.yaml_vars, state.variables),
    cwd = root,
  })

  if err then
    notify.error(err)
    return false
  end

  notify.info("Pipeline triggered for " .. state.project .. " on " .. state.ref)

  -- `glab ci run` has no structured output containing the created pipeline ID,
  -- so use the most recent pipeline for this ref. Concurrent pipeline creation
  -- on the same project/ref can make this association ambiguous.
  local pipeline = api.latest_pipeline({
    project = state.project,
    ref = state.ref,
    cwd = root,
  })
  if pipeline and pipeline.id then
    pipeline_watch.watch({
      pipeline_id = pipeline.id,
      project = state.project,
      root = root,
    })
  end

  return true
end

local function fetch_inputs(state)
  if state.project == "" or state.ref == "" then
    return nil, "project and ref are required"
  end

  local inputs, err, yaml_vars = api.pipeline_inputs({
    project = state.project,
    ref = state.ref,
    cwd = state.root or vim.fn.getcwd(),
  })

  if err then
    notification.warn("Could not fetch CI config for " .. state.project .. ": " .. err)
    return nil, err
  end

  -- spec:inputs → state.fields
  if not inputs or #inputs == 0 then
    state.fields = {}
  else
    local existing = {}
    for _, f in ipairs(state.fields) do
      existing[f.name] = f.value
    end

    state.fields = {}
    for _, input in ipairs(inputs) do
      table.insert(state.fields, {
        name = input.name,
        description = input.description or "",
        type = input.type or "string",
        default = input.default,
        options = input.options,
        value = existing[input.name] ~= nil and existing[input.name]
          or (input.default ~= nil and tostring(input.default)
            or (input.options and #input.options > 0 and input.options[1] or "")),
      })
    end
  end

  -- legacy described YAML variables → state.yaml_vars
  -- Edits are preserved only when project+ref are unchanged.
  local new_key = state.project .. "|" .. state.ref
  local existing_yaml = {}
  if state.yaml_vars_key == new_key then
    for _, yv in ipairs(state.yaml_vars) do
      existing_yaml[yv.key] = yv.value
    end
  end

  state.yaml_vars = {}
  for _, v in ipairs(yaml_vars or {}) do
    local entry = vim.tbl_extend("force", {}, v)
    entry.value = existing_yaml[v.key] ~= nil and existing_yaml[v.key] or (v.value or "")
    table.insert(state.yaml_vars, entry)
  end
  state.yaml_vars_key = new_key
  return true, nil
end

local function change_project(state, candidate, get_project, discover)
  local previous_project = state.committed_project or state.project_fallback or ""
  local previous_ref = state.ref
  candidate = vim.trim(tostring(candidate or ""))

  if candidate == "" then
    state.project = previous_project
    state.ref = previous_ref
    return nil, "project is required"
  end

  if state.committed_project and candidate == state.committed_project then
    state.project = state.committed_project
    return true, false
  end

  local project, err = get_project({
    project = candidate,
    cwd = state.root or vim.fn.getcwd(),
  })
  if not project then
    state.project = previous_project
    state.ref = previous_ref
    return nil, err
  end
  if type(project.path_with_namespace) ~= "string" or project.path_with_namespace == "" then
    state.project = previous_project
    state.ref = previous_ref
    return nil, "Project metadata is missing path_with_namespace"
  end
  if type(project.default_branch) ~= "string" or project.default_branch == "" then
    state.project = previous_project
    state.ref = previous_ref
    return nil, "Project has no default branch"
  end

  local canonical_project = project.path_with_namespace
  local canonicalizing_fallback = not state.committed_project and candidate == state.project_fallback
  if canonical_project == previous_project or canonicalizing_fallback then
    state.project = canonical_project
    state.committed_project = canonical_project
    state.project_fallback = canonical_project
    return true, false
  end

  state.project = canonical_project
  state.committed_project = canonical_project
  state.project_fallback = canonical_project
  state.ref = project.default_branch
  state.fields = {}
  state.yaml_vars = {}
  state.yaml_vars_key = ""
  -- Metadata is authoritative once resolved. Discovery failure must not roll
  -- Project/Ref back to the previous repository; stale discovered state stays
  -- cleared while manual state.variables remains untouched.
  discover(state)
  return true, true
end

local function open_project_picker(state, close_runner, select_project, discover, rebuild, notify)
  local previous_project = state.project
  local previous_ref = state.ref
  local completed = false
  close_runner()
  select_project({ cwd = state.root or vim.fn.getcwd() }, function(selected)
    if completed then
      return
    end
    completed = true
    if not selected then
      state.project = previous_project
      state.ref = previous_ref
      rebuild({ focus_project = true })
      return
    end

    local ok, changed_or_err = change_project(
      state,
      selected.path_with_namespace,
      -- Project picker entries already came from api.projects(); reuse that
      -- normalized metadata and never issue a second api.project() request.
      function() return selected, nil end,
      discover
    )
    if not ok then
      notify.error("Could not change project: " .. tostring(changed_or_err))
      rebuild({ focus_project = true })
      return
    end
    rebuild(changed_or_err and { focus_ref = true } or { focus_project = true })
  end)
end

local function configure_project_picker_mapping(components, on_pick_project)
  for _, component in ipairs(components) do
    component:map("i", "<C-p>", function()
      vim.cmd("stopinsert")
      on_pick_project()
    end, { noremap = true })
    component:map("n", "<C-p>", on_pick_project, { noremap = true })
  end
end

local function configure_ref_picker_mapping(components, on_pick_ref)
  for _, component in ipairs(components) do
    -- Intentionally shadow insert-mode <C-r> (insert register) inside runner
    -- buffers so Ref picking remains a consistent runner-global action.
    component:map("i", "<C-r>", function()
      vim.cmd("stopinsert")
      on_pick_ref()
    end, { noremap = true })
    component:map("n", "<C-r>", on_pick_ref, { noremap = true })
  end
end

-- make_desc_popup creates a non-focusable, borderless popup for description text.
local function make_desc_popup()
  return Popup({
    border = { style = "none" },
    win_options = { winhighlight = "Normal:Comment" },
    buf_options = { modifiable = false, readonly = false },
    focusable = false,
  })
end

local function build_and_mount(
  state,
  on_run,
  on_pick_project,
  on_pick_ref,
  on_add_variable,
  on_remove_variable,
  on_close,
  on_submit_project,
  on_submit_ref
)
  local hint_lines = runner_hint_lines()
  local hints_size = #hint_lines
  local project_input = make_input("Project", state.project, function(v)
    state.project = v
  end, on_submit_project)

  local ref_input = make_input("Ref / Branch", state.ref, function(v)
    state.ref = v
  end, on_submit_ref)

  -- Each entry: { input=Input|Menu, size=number, menu_entry=table|nil, desc=Popup|nil, desc_text=string|nil }
  local field_entries = {}
  for _, field in ipairs(state.fields) do
    local f = field
    local input, size, menu_entry = make_field_component(f, field_label(f))
    local desc_popup, desc_text
    if f.description and f.description ~= "" then
      desc_popup = make_desc_popup()
      desc_text = sanitize_ui(f.description)
    end
    table.insert(field_entries, {
      input = input, size = size, menu_entry = menu_entry,
      desc = desc_popup, desc_text = desc_text,
    })
  end

  local yaml_var_entries = {}
  for _, yv in ipairs(state.yaml_vars) do
    local y = yv
    local input, size, menu_entry = make_field_component(y, sanitize_ui(y.key))
    local desc_popup, desc_text
    if y.description and y.description ~= "" then
      desc_popup = make_desc_popup()
      desc_text = sanitize_ui(y.description)
    end
    table.insert(yaml_var_entries, {
      input = input, size = size, menu_entry = menu_entry,
      desc = desc_popup, desc_text = desc_text,
    })
  end

  local var_inputs = {}
  for _, var in ipairs(state.variables) do
    local v = var
    local display = v.key ~= "" and (v.key .. "=" .. v.value) or ""
    local input = make_input("Variable (KEY=VALUE)", display, function(raw)
      local eq = raw:find("=")
      if eq then
        v.key = raw:sub(1, eq - 1)
        v.value = raw:sub(eq + 1)
      else
        v.key = raw
        v.value = ""
      end
    end)
    table.insert(var_inputs, input)
  end

  local hints_popup = Popup({
    border = { style = "rounded" },
    win_options = { winhighlight = "Normal:Normal" },
    buf_options = { modifiable = false, readonly = false },
    focusable = false,
  })

  local form_frame = Popup({
    border = {
      style = "rounded",
      text = { top = " Pipeline ", top_align = "left" },
    },
    focusable = false,
  })

  local scrollbar = Popup({
    border = { style = "none" },
    win_options = { winhighlight = "Normal:Comment" },
    buf_options = { modifiable = false, readonly = false },
    focusable = false,
  })

  -- A viewport item can contain a focusable component and its non-focusable
  -- description. Layout:update mounts only the currently visible item boxes.
  local viewport_items = {}
  local function add_viewport_item(component, size, desc)
    local boxes = { Layout.Box(component, { size = size }) }
    local total = size
    if desc then
      table.insert(boxes, Layout.Box(desc, { size = 1 }))
      total = total + 1
    end
    table.insert(viewport_items, {
      component = component,
      size = total,
      box = Layout.Box(boxes, { dir = "col", size = total }),
    })
  end

  add_viewport_item(project_input, 3)
  add_viewport_item(ref_input, 3)
  for _, entries in ipairs({ field_entries, yaml_var_entries }) do
    for _, entry in ipairs(entries) do
      add_viewport_item(entry.input, entry.size, entry.desc)
    end
  end
  for _, input in ipairs(var_inputs) do
    add_viewport_item(input, 3)
  end

  local viewport = { offset = 1, focus_index = 1 }
  local layout
  local form_layout
  local sync_menu_positions
  local function form_layout_box()
    local first, last = viewport_range(viewport_items, viewport.offset, FORM_VIEWPORT_HEIGHT)
    local visible = {}
    for i = first, last do
      table.insert(visible, viewport_items[i].box)
    end
    return Layout.Box({
      Layout.Box(visible, { dir = "col", grow = 1 }),
      Layout.Box(scrollbar, { size = 1 }),
    }, { dir = "row" })
  end

  local function update_scrollbar()
    local lines = viewport_scrollbar_lines(viewport_items, viewport.offset, FORM_VIEWPORT_HEIGHT)
    vim.bo[scrollbar.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(scrollbar.bufnr, 0, -1, false, lines)
    vim.bo[scrollbar.bufnr].modifiable = false
  end

  layout = Layout(
    { position = "50%", size = { width = RUNNER_WIDTH, height = FRAME_HEIGHT } },
    Layout.Box({
      Layout.Box(form_frame, { size = { width = RUNNER_WIDTH - LEGEND_WIDTH, height = FRAME_HEIGHT } }),
      Layout.Box(hints_popup, { size = { width = LEGEND_WIDTH, height = FRAME_HEIGHT } }),
    }, { dir = "row" })
  )

  function viewport.render()
    if form_layout and form_layout.winid then
      form_layout:update(form_layout_box())
      update_scrollbar()
      if sync_menu_positions then
        sync_menu_positions()
      end
    end
  end

  function viewport.ensure_visible(index)
    local offset = viewport_offset_for_focus(viewport_items, viewport.offset, FORM_VIEWPORT_HEIGHT, index)
    if offset ~= viewport.offset then
      viewport.offset = offset
      viewport.render()
    end
  end

  layout:mount()
  form_layout = Layout(form_frame, form_layout_box())
  form_layout:mount()
  update_scrollbar()

  local layout_unmount = layout.unmount
  function layout:unmount()
    if form_layout then
      form_layout:unmount()
      form_layout = nil
    end
    layout_unmount(self)
  end

  sync_menu_positions = function()
    for _, entries in ipairs({ field_entries, yaml_var_entries }) do
      for _, entry in ipairs(entries) do
        if entry.menu_entry then
          local selected = entry.menu_entry.selected_index
          if entry.input.winid and vim.api.nvim_win_is_valid(entry.input.winid) then
            if selected then
              vim.api.nvim_win_set_cursor(entry.input.winid, { selected, 0 })
            end
            entry.menu_entry.initializing = false
          end
        end
      end
    end
  end
  sync_menu_positions()

  -- Populate hints and description text after mount.
  vim.bo[hints_popup.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(hints_popup.bufnr, 0, -1, false, hint_lines)
  vim.bo[hints_popup.bufnr].modifiable = false

  local function populate_descs(entries)
    for _, e in ipairs(entries) do
      if e.desc and e.desc_text then
        vim.bo[e.desc.bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(e.desc.bufnr, 0, -1, false, { "  " .. e.desc_text })
        vim.bo[e.desc.bufnr].modifiable = false
      end
    end
  end
  populate_descs(field_entries)
  populate_descs(yaml_var_entries)

  -- Viewport items map one-to-one to focusable components. Descriptions and
  -- the legend are deliberately absent from this order.
  local tab_order = {}
  for _, item in ipairs(viewport_items) do
    table.insert(tab_order, item.component)
  end

  configure_tab_navigation(tab_order, viewport)
  configure_component_mappings(tab_order, {
    run = on_run,
    add_variable = on_add_variable,
    close = on_close,
  })

  for index, component in ipairs(var_inputs) do
    component:map("n", "d", function()
      on_remove_variable(index)
    end, { noremap = true })
  end

  configure_ref_picker_mapping(tab_order, on_pick_ref)
  configure_project_picker_mapping(tab_order, on_pick_project)

  return layout, project_input, ref_input, var_inputs, viewport
end

function M.open()
  local ctx, ctx_err = context.from_cwd()

  local state = {
    project = ctx and ctx.project or "",
    committed_project = nil,
    project_fallback = ctx and ctx.project or "",
    ref = ctx and ctx.ref or "",
    root = ctx and ctx.root or nil,
    fields = {},
    yaml_vars = {},
    yaml_vars_key = "",
    variables = {},
  }

  local current_layout = nil

  local function close()
    if current_layout then
      current_layout:unmount()
      current_layout = nil
    end
  end

  local function run()
    submit_pipeline(state, close, notification, glab.run_pipeline)
  end

  local build        -- forward declaration for mutual reference with pick_ref / on_submit_*
  local add_variable -- forward declaration for mutual reference with build
  local remove_variable
  local on_submit_project
  local on_submit_ref

  local function pick_ref()
    if state.project == "" then
      notification.warn("Set project before picking a ref")
      return
    end

    notification.info("Fetching refs for " .. state.project .. "...")

    local branches, err = api.branches({
      project = state.project,
      cwd = state.root or vim.fn.getcwd(),
    })

    if err then
      notification.error("Could not fetch branches: " .. err)
      return
    end

    if not branches or #branches == 0 then
      notification.warn("No branches found for " .. state.project)
      return
    end

    open_ref_picker(state, branches, close, fetch_inputs, build, picker.select)
  end

  local function pick_project()
    open_project_picker(state, close, project_picker.select, fetch_inputs, build, notification)
  end

  add_variable = function()
    table.insert(state.variables, { key = "", value = "" })
    build({ focus_last_var = true })
  end

  remove_variable = function(index)
    local removed, focus_opts = remove_added_variable(state, index)
    if not removed then
      return
    end
    build(focus_opts)
  end

  on_submit_project = function()
    local ok, changed_or_err = change_project(state, state.project, api.project, fetch_inputs)
    if not ok then
      notification.error("Could not change project: " .. tostring(changed_or_err))
      build()
      return
    end
    build({ focus_ref = changed_or_err })
  end

  on_submit_ref = function()
    if state.ref == "" then
      return
    end
    fetch_inputs(state)
    build()
  end

  build = function(opts)
    opts = opts or {}

    if current_layout then
      current_layout:unmount()
      current_layout = nil
    end

    local layout, project_input, ref_input, var_inputs, viewport =
      build_and_mount(
        state,
        run,
        pick_project,
        pick_ref,
        add_variable,
        remove_variable,
        close,
        on_submit_project,
        on_submit_ref
      )
    current_layout = layout

  -- Schedule focus so it fires after NUI completes its async mount tick.
  -- This ensures startinsert! lands in a fully-created window, giving the user
  -- immediate insert mode without needing to press `i`.
  vim.schedule(function()
    local target = project_input
    local target_index = 1
    if opts.focus_variable_index and var_inputs and var_inputs[opts.focus_variable_index] then
      target = var_inputs[opts.focus_variable_index]
      target_index = 2 + #state.fields + #state.yaml_vars + opts.focus_variable_index
    elseif opts.focus_last_var and var_inputs and #var_inputs > 0 then
      target = var_inputs[#var_inputs]
      target_index = 2 + #state.fields + #state.yaml_vars + #var_inputs
    elseif opts.focus_ref then
      target = ref_input
      target_index = 2
    end
    viewport.focus_index = target_index
    viewport.ensure_visible(target_index)
    focus(target)
  end)
  end

  fetch_inputs(state)
  build()

  if not ctx then
    notification.warn(ctx_err or "Could not detect project context — enter project and ref manually")
  end
end

M._fetch_inputs = fetch_inputs
M._change_project = change_project
M._open_project_picker = open_project_picker
M._configure_project_picker_mapping = configure_project_picker_mapping
M._configure_ref_picker_mapping = configure_ref_picker_mapping
M._merge_variables = merge_variables
M._sanitize_ui = sanitize_ui
M._option_index = option_index
M._validate_option_values = validate_option_values
M._collect_inputs = collect_inputs
M._make_field_component = make_field_component
M._configure_tab_navigation = configure_tab_navigation
M._viewport_range = viewport_range
M._viewport_offset_for_focus = viewport_offset_for_focus
M._viewport_scrollbar_lines = viewport_scrollbar_lines
M._form_viewport_height = FORM_VIEWPORT_HEIGHT
M._configure_component_mappings = configure_component_mappings
M._runner_layout_spec = runner_layout_spec
M._open_ref_picker = open_ref_picker
M._runner_hint_lines = runner_hint_lines
M._remove_added_variable = remove_added_variable
M._submit_pipeline = submit_pipeline

return M
