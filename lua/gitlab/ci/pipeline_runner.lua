local Input = require("nui.input")
local Layout = require("nui.layout")
local Popup = require("nui.popup")

local api = require("gitlab.api")
local git = require("gitlab.git")
local glab = require("gitlab.glab")
local notification = require("gitlab.ui.notification")

local M = {}

local MAX_DYNAMIC_FIELDS = 7
local HINTS_SIZE = 3

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

local function fetch_inputs(state)
  if state.project == "" or state.ref == "" then
    return
  end

  local inputs, _ = api.pipeline_inputs({
    project = state.project,
    ref = state.ref,
    cwd = git.root() or vim.fn.getcwd(),
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

local function build_and_mount(state, on_run, on_refresh, on_close)
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

  local hints_popup = Popup({
    border = { style = "none" },
    win_options = { winhighlight = "Normal:Normal" },
    buf_options = { modifiable = false, readonly = false },
  })

  local n_dynamic = #field_inputs
  local height = (2 + n_dynamic) * 3 + HINTS_SIZE

  local boxes = {
    Layout.Box(project_input, { size = 3 }),
    Layout.Box(ref_input, { size = 3 }),
  }
  for _, fi in ipairs(field_inputs) do
    table.insert(boxes, Layout.Box(fi, { size = 3 }))
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
  })
  vim.bo[hints_popup.bufnr].modifiable = false

  local tab_order = { project_input, ref_input }
  for _, fi in ipairs(field_inputs) do
    table.insert(tab_order, fi)
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

    component:map("i", "<Esc>", function()
      vim.cmd("stopinsert")
    end, { noremap = true })

    component:map("n", "q", on_close, { noremap = true })
    component:map("n", "<Esc>", on_close, { noremap = true })
  end

  return layout, project_input
end

function M.open()
  local state = {
    project = git.remote_project() or "",
    ref = git.branch() or "",
    fields = {},
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
      cwd = git.root() or vim.fn.getcwd(),
    })

    if err then
      notification.error(err)
      return
    end

    notification.info("Pipeline triggered for " .. state.project .. " on " .. state.ref)
  end

  local refresh  -- forward declaration for mutual reference with build

  local function build()
    if current_layout then
      current_layout:unmount()
      current_layout = nil
    end

    local layout, first_input = build_and_mount(state, run, function() refresh() end, close)
    current_layout = layout
    focus(first_input)
  end

  refresh = function()
    if state.project == "" or state.ref == "" then
      notification.warn("Set project and ref before refreshing")
      return
    end

    notification.info("Fetching pipeline inputs for " .. state.project .. "...")
    fetch_inputs(state)
    build()

    if #state.fields > 0 then
      notification.info("Found " .. #state.fields .. " pipeline input(s)")
    else
      notification.info("No pipeline inputs configured")
    end
  end

  fetch_inputs(state)
  build()

  if state.project == "" then
    notification.warn("Could not detect GitLab project — enter it manually")
  end
end

return M
