local Input = require("nui.input")
local Layout = require("nui.layout")
local Popup = require("nui.popup")

local api = require("gitlab.api")
local context = require("gitlab.ci.context")
local glab = require("gitlab.glab")
local notification = require("gitlab.ui.notification")
local picker = require("gitlab.ui.picker")

local M = {}

local MAX_DYNAMIC_FIELDS = 7
local MAX_VARIABLES = 7 -- UI layout limit, not a GitLab restriction
local HINTS_SIZE = 4

-- merge_variables builds the final variable list for the pipeline trigger.
-- Project variables go first; manual variables override matching keys.
-- The result contains no duplicate keys.
local function merge_variables(project_vars, manual_vars)
  local seen = {}
  local result = {}

  for _, pv in ipairs(project_vars) do
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

local function make_input(label, default, on_change)
  return Input({
    border = {
      style = "rounded",
      text = { top = " " .. label .. " ", top_align = "left" },
    },
  }, {
    prompt = "",
    default_value = default or "",
    on_change = on_change,
    on_submit = function() end,
  })
end

local function focus(component)
  if component and component.winid and vim.api.nvim_win_is_valid(component.winid) then
    vim.api.nvim_set_current_win(component.winid)
    vim.cmd("startinsert!")
  end
end

local function field_label(field)
  local label = field.name

  if field.options and #field.options > 0 then
    label = label .. " (" .. table.concat(field.options, " | ") .. ")"
  elseif field.description and field.description ~= "" then
    label = label .. " — " .. field.description
  end

  return label
end

-- normalize_project_vars filters raw API variables to those with a non-empty
-- description and applies edited-value preservation: a value the user already
-- typed overrides the freshly fetched API value.
-- Full variable metadata from the API is preserved on each entry.
local function normalize_project_vars(raw_vars, existing)
  existing = existing or {}
  local result = {}
  for _, v in ipairs(raw_vars or {}) do
    if v.description and v.description ~= "" then
      local entry = vim.tbl_extend("force", {}, v)
      entry.value = (existing[v.key] ~= nil and existing[v.key]) or (v.value or "")
      table.insert(result, entry)
    end
  end
  return result
end

local function fetch_project_vars(state)
  if state.project == "" then
    return
  end

  local vars, _ = api.variables({
    project = state.project,
    cwd = state.root or vim.fn.getcwd(),
  })

  -- Only carry forward edited values when refreshing the same project.
  -- A project change discards previous edits so stale values do not leak.
  local existing = {}
  if state.project_vars_project == state.project then
    for _, pv in ipairs(state.project_vars) do
      existing[pv.key] = pv.value
    end
  end

  state.project_vars = normalize_project_vars(vars, existing)
  state.project_vars_project = state.project
end

local function fetch_inputs(state)
  if state.project == "" or state.ref == "" then
    return
  end

  local inputs, _ = api.pipeline_inputs({
    project = state.project,
    ref = state.ref,
    cwd = state.root or vim.fn.getcwd(),
  })

  if not inputs or #inputs == 0 then
    state.fields = {}
    return
  end

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
      value = existing[input.name] or tostring(input.default or ""),
    })
  end
end

local function build_and_mount(state, on_run, on_refresh, on_pick_ref, on_add_variable, on_close)
  local project_input = make_input("Project", state.project, function(v)
    state.project = v
  end)

  local ref_input = make_input("Ref / Branch", state.ref, function(v)
    state.ref = v
  end)

  local field_inputs = {}
  for _, field in ipairs(state.fields) do
    local f = field
    local input = make_input(field_label(f), f.value, function(v)
      f.value = v
    end)
    table.insert(field_inputs, input)
  end

  local proj_var_inputs = {}
  for _, pv in ipairs(state.project_vars) do
    local p = pv
    local label = p.key .. " — " .. p.description
    local input = make_input(label, p.value, function(v)
      p.value = v
    end)
    table.insert(proj_var_inputs, input)
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

  local n_dynamic = #field_inputs
  local n_proj_vars = #proj_var_inputs
  local n_vars = #var_inputs
  local height = (2 + n_dynamic + n_proj_vars + n_vars) * 3 + HINTS_SIZE

  local boxes = {
    Layout.Box(project_input, { size = 3 }),
    Layout.Box(ref_input, { size = 3 }),
  }
  for _, fi in ipairs(field_inputs) do
    table.insert(boxes, Layout.Box(fi, { size = 3 }))
  end
  for _, pvi in ipairs(proj_var_inputs) do
    table.insert(boxes, Layout.Box(pvi, { size = 3 }))
  end
  for _, vi in ipairs(var_inputs) do
    table.insert(boxes, Layout.Box(vi, { size = 3 }))
  end
  table.insert(boxes, Layout.Box(hints_popup, { size = HINTS_SIZE }))

  local layout = Layout(
    { position = "50%", size = { width = 60, height = height } },
    Layout.Box(boxes, { dir = "col" })
  )

  layout:mount()

  vim.bo[hints_popup.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(hints_popup.bufnr, 0, -1, false, {
    "",
    "  Tab  Next field    r  Refresh    <CR>  Run    q  Close",
    "  <C-r>  Pick ref (Ref field)    a  Add variable",
    "",
  })
  vim.bo[hints_popup.bufnr].modifiable = false

  local tab_order = { project_input, ref_input }
  for _, fi in ipairs(field_inputs) do
    table.insert(tab_order, fi)
  end
  for _, pvi in ipairs(proj_var_inputs) do
    table.insert(tab_order, pvi)
  end
  for _, vi in ipairs(var_inputs) do
    table.insert(tab_order, vi)
  end

  for i, component in ipairs(tab_order) do
    local next_idx = (i % #tab_order) + 1
    local prev_idx = ((i - 2) % #tab_order) + 1

    component:map("i", "<Tab>", function()
      focus(tab_order[next_idx])
    end, { noremap = true })

    component:map("i", "<S-Tab>", function()
      focus(tab_order[prev_idx])
    end, { noremap = true })

    component:map("i", "<CR>", on_run, { noremap = true })
    component:map("n", "<CR>", on_run, { noremap = true })

    component:map("n", "r", on_refresh, { noremap = true })
    component:map("n", "a", on_add_variable, { noremap = true })

    component:map("i", "<Esc>", function()
      vim.cmd("stopinsert")
    end, { noremap = true })

    component:map("n", "q", on_close, { noremap = true })
    component:map("n", "<Esc>", on_close, { noremap = true })
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
    project_vars = {},
    project_vars_project = "",
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
    if state.project == "" then
      notification.error("Project is required")
      return
    end

    if not state.project:match("^[^/]+/[^/]+") then
      notification.error("Project must be in namespace/project format")
      return
    end

    if state.ref == "" then
      notification.error("Ref is required")
      return
    end

    local inputs = {}
    for _, field in ipairs(state.fields) do
      table.insert(inputs, { name = field.name, value = field.value, type = field.type })
    end

    notification.info("Running pipeline on " .. state.ref .. " for " .. state.project .. "...")

    local _, err = glab.run_pipeline({
      project = state.project,
      ref = state.ref,
      inputs = inputs,
      variables = merge_variables(state.project_vars, state.variables),
      cwd = state.root or vim.fn.getcwd(),
    })

    if err then
      notification.error(err)
      return
    end

    notification.info("Pipeline triggered for " .. state.project .. " on " .. state.ref)
  end

  local refresh      -- forward declaration for mutual reference with build
  local build        -- forward declaration for mutual reference with pick_ref
  local add_variable -- forward declaration for mutual reference with build

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

    picker.select(branches, { prompt = "Select ref" }, function(selected)
      if not selected then
        return
      end
      state.ref = selected
      build({ focus_ref = true })
    end)
  end

  add_variable = function()
    if #state.variables >= MAX_VARIABLES then
      notification.warn("Maximum number of variables reached (" .. MAX_VARIABLES .. ")")
      return
    end
    table.insert(state.variables, { key = "", value = "" })
    build({ focus_last_var = true })
  end

  build = function(opts)
    opts = opts or {}

    if current_layout then
      current_layout:unmount()
      current_layout = nil
    end

    local layout, project_input, ref_input, var_inputs =
      build_and_mount(state, run, function() refresh() end, pick_ref, add_variable, close)
    current_layout = layout

    if opts.focus_last_var and var_inputs and #var_inputs > 0 then
      focus(var_inputs[#var_inputs])
    elseif opts.focus_ref then
      focus(ref_input)
    else
      focus(project_input)
    end
  end

  refresh = function()
    if state.project == "" or state.ref == "" then
      notification.warn("Set project and ref before refreshing")
      return
    end

    notification.info("Fetching pipeline inputs for " .. state.project .. "...")
    fetch_inputs(state)
    fetch_project_vars(state)
    build()

    if #state.fields > 0 then
      notification.info("Found " .. #state.fields .. " pipeline input(s)")
    else
      notification.info("No pipeline inputs configured")
    end
  end

  fetch_inputs(state)
  fetch_project_vars(state)
  build()

  if not ctx then
    notification.warn(ctx_err or "Could not detect project context — enter project and ref manually")
  end
end

M.normalize_project_vars = normalize_project_vars
M.fetch_project_vars = fetch_project_vars
M.merge_variables = merge_variables

return M
