local Input = require("nui.input")
local Layout = require("nui.layout")
local Menu = require("nui.menu")
local Popup = require("nui.popup")

local api = require("gitlab.api")
local context = require("gitlab.ci.context")
local glab = require("gitlab.glab")
local notification = require("gitlab.ui.notification")
local picker = require("gitlab.ui.picker")

local M = {}

local MAX_DYNAMIC_FIELDS = 7
local MAX_VARIABLES = 7 -- UI layout limit, not a GitLab restriction

local function runner_hint_lines()
  return {
    "",
    "  <Tab>    Next field",
    "  <S-Tab>  Previous field",
    "  j / k    Choose option",
    "  <C-r>    Pick ref (Ref field)",
    "  a        Add variable",
    "  d        Remove added variable",
    "  <CR>     Run",
    "  q / <Esc>  Close",
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
      end
    end,
  })
  menu._gitlab_component_kind = "menu"
  entry.component = menu
  return menu, height + 2, entry
end

local function configure_tab_navigation(tab_order)
  for i, component in ipairs(tab_order) do
    local next_idx = (i % #tab_order) + 1
    local prev_idx = ((i - 2) % #tab_order) + 1

    component:map("i", "<Tab>", function()
      vim.cmd("stopinsert")
      vim.schedule(function() focus(tab_order[next_idx]) end)
    end, { noremap = true })
    component:map("n", "<Tab>", function()
      vim.schedule(function() focus(tab_order[next_idx]) end)
    end, { noremap = true })
    component:map("i", "<S-Tab>", function()
      vim.cmd("stopinsert")
      vim.schedule(function() focus(tab_order[prev_idx]) end)
    end, { noremap = true })
    component:map("n", "<S-Tab>", function()
      vim.schedule(function() focus(tab_order[prev_idx]) end)
    end, { noremap = true })
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

  -- Variable priority: YAML described vars < manual user vars.
  local _, err = trigger({
    project = state.project,
    ref = state.ref,
    inputs = inputs,
    variables = merge_variables(state.yaml_vars, state.variables),
    cwd = state.root or vim.fn.getcwd(),
  })

  if err then
    notify.error(err)
    return false
  end

  notify.info("Pipeline triggered for " .. state.project .. " on " .. state.ref)
  return true
end

local function fetch_inputs(state)
  if state.project == "" or state.ref == "" then
    return
  end

  local inputs, err, yaml_vars = api.pipeline_inputs({
    project = state.project,
    ref = state.ref,
    cwd = state.root or vim.fn.getcwd(),
  })

  if err then
    notification.warn("Could not fetch CI config for " .. state.project .. ": " .. err)
    return
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
    for i, input in ipairs(inputs) do
      if i > MAX_DYNAMIC_FIELDS then
        break
      end
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

local function build_and_mount(state, on_run, on_pick_ref, on_add_variable, on_remove_variable, on_close, on_submit_project, on_submit_ref)
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
    border = { style = "none" },
    win_options = { winhighlight = "Normal:Normal" },
    buf_options = { modifiable = false, readonly = false },
  })

  local function count_descs(entries)
    local n = 0
    for _, e in ipairs(entries) do if e.desc then n = n + 1 end end
    return n
  end

  local n_vars = #var_inputs
  local n_descs = count_descs(field_entries) + count_descs(yaml_var_entries)
  local height = 2 * 3 + n_vars * 3 + n_descs + hints_size
  for _, entries in ipairs({ field_entries, yaml_var_entries }) do
    for _, entry in ipairs(entries) do height = height + entry.size end
  end

  local boxes = {
    Layout.Box(project_input, { size = 3 }),
    Layout.Box(ref_input, { size = 3 }),
  }
  local function add_entries(entries)
    for _, e in ipairs(entries) do
      table.insert(boxes, Layout.Box(e.input, { size = e.size }))
      if e.desc then
        table.insert(boxes, Layout.Box(e.desc, { size = 1 }))
      end
    end
  end
  add_entries(field_entries)
  add_entries(yaml_var_entries)
  for _, vi in ipairs(var_inputs) do
    table.insert(boxes, Layout.Box(vi, { size = 3 }))
  end
  table.insert(boxes, Layout.Box(hints_popup, { size = hints_size }))

  local layout = Layout(
    { position = "50%", size = { width = 60, height = height } },
    Layout.Box(boxes, { dir = "col" })
  )

  layout:mount()

  for _, entries in ipairs({ field_entries, yaml_var_entries }) do
    for _, entry in ipairs(entries) do
      if entry.menu_entry then
        local selected = entry.menu_entry.selected_index
        if selected and entry.input.winid and vim.api.nvim_win_is_valid(entry.input.winid) then
          vim.api.nvim_win_set_cursor(entry.input.winid, { selected, 0 })
        end
        entry.menu_entry.initializing = false
      end
    end
  end

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

  -- Tab order contains only focusable inputs; desc popups are intentionally excluded.
  local tab_order = { project_input, ref_input }
  local function add_inputs_to_tab(entries)
    for _, e in ipairs(entries) do
      table.insert(tab_order, e.input)
    end
  end
  add_inputs_to_tab(field_entries)
  add_inputs_to_tab(yaml_var_entries)
  for _, vi in ipairs(var_inputs) do
    table.insert(tab_order, vi)
  end

  -- project_input and ref_input commit on Enter (via on_submit); all other fields run the pipeline.
  local commit_components = { [project_input] = true, [ref_input] = true }

  configure_tab_navigation(tab_order)

  for _, component in ipairs(tab_order) do
    if not commit_components[component] then
      component:map("i", "<CR>", on_run, { noremap = true })
      component:map("n", "<CR>", on_run, { noremap = true })
    end

    component:map("n", "a", on_add_variable, { noremap = true })

    component:map("i", "<Esc>", function()
      vim.cmd("stopinsert")
    end, { noremap = true })

    component:map("n", "q", on_close, { noremap = true })
    component:map("n", "<Esc>", on_close, { noremap = true })
  end

  for index, component in ipairs(var_inputs) do
    component:map("n", "d", function()
      on_remove_variable(index)
    end, { noremap = true })
  end

  ref_input:map("i", "<C-r>", function()
    vim.cmd("stopinsert")
    on_pick_ref()
  end, { noremap = true })

  ref_input:map("n", "<C-r>", on_pick_ref, { noremap = true })

  return layout, project_input, ref_input, var_inputs
end

function M.open()
  local ctx, ctx_err = context.from_cwd()

  local state = {
    project = ctx and ctx.project or "",
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

  add_variable = function()
    if #state.variables >= MAX_VARIABLES then
      notification.warn("Maximum number of variables reached (" .. MAX_VARIABLES .. ")")
      return
    end
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
    if state.project == "" then
      return
    end
    fetch_inputs(state)
    build()
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

    local layout, project_input, ref_input, var_inputs =
      build_and_mount(state, run, pick_ref, add_variable, remove_variable, close, on_submit_project, on_submit_ref)
    current_layout = layout

  -- Schedule focus so it fires after NUI completes its async mount tick.
  -- This ensures startinsert! lands in a fully-created window, giving the user
  -- immediate insert mode without needing to press `i`.
  vim.schedule(function()
    if opts.focus_variable_index and var_inputs and var_inputs[opts.focus_variable_index] then
      focus(var_inputs[opts.focus_variable_index])
    elseif opts.focus_last_var and var_inputs and #var_inputs > 0 then
      focus(var_inputs[#var_inputs])
    elseif opts.focus_ref then
      focus(ref_input)
    else
      focus(project_input)
    end
  end)
  end

  fetch_inputs(state)
  build()

  if not ctx then
    notification.warn(ctx_err or "Could not detect project context — enter project and ref manually")
  end
end

M._fetch_inputs = fetch_inputs
M._merge_variables = merge_variables
M._sanitize_ui = sanitize_ui
M._option_index = option_index
M._validate_option_values = validate_option_values
M._collect_inputs = collect_inputs
M._make_field_component = make_field_component
M._configure_tab_navigation = configure_tab_navigation
M._open_ref_picker = open_ref_picker
M._runner_hint_lines = runner_hint_lines
M._remove_added_variable = remove_added_variable
M._submit_pipeline = submit_pipeline

return M
