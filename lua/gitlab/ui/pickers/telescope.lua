local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local telescope_actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local M = {}

function M.select(items, opts, callback)
  opts = opts or {}

  local function format_item(item)
    if opts.format_item then
      return opts.format_item(item)
    end

    return tostring(item)
  end

  local function preview_lines(item)
    local lines = {
      "<CR>  " .. (opts.select_label or "Select"),
    }

    for _, action in ipairs(opts.actions or {}) do
      table.insert(lines, action.key .. "  " .. action.label)
    end

    if opts.preview and item then
      table.insert(lines, "")
      vim.list_extend(lines, opts.preview(item) or {})
    end

    return lines
  end

  local details_previewer = previewers.new_buffer_previewer({
    title = "Details",

    define_preview = function(self, entry)
      local item = entry and entry.value or nil

      vim.api.nvim_buf_set_lines(
        self.state.bufnr,
        0,
        -1,
        false,
        preview_lines(item)
      )
    end,
  })

  local picker_opts = {
    layout_strategy = "horizontal",
    layout_config = {
      width = 0.9,
      height = math.min(#items + 6, 18),
      preview_width = 0.25,
    },
  }

  pickers.new(picker_opts, {
    prompt_title = opts.prompt or "Select",
    results_title = "Results",
    previewer = details_previewer,

    finder = finders.new_table({
      results = items,
      entry_maker = function(item)
        local display = format_item(item)

        return {
          value = item,
          display = display,
          ordinal = display,
        }
      end,
    }),

    sorter = conf.generic_sorter({}),

    attach_mappings = function(prompt_bufnr, map)
      local function selected_item()
        local entry = action_state.get_selected_entry()
        return entry and entry.value or nil
      end

      local function run_picker_action(action)
        local item = selected_item()

        if not item then
          return
        end

        telescope_actions.close(prompt_bufnr)
        action.callback(item)
      end

      telescope_actions.select_default:replace(function()
        local item = selected_item()

        telescope_actions.close(prompt_bufnr)

        if item and callback then
          callback(item)
        end
      end)

      for _, picker_action in ipairs(opts.actions or {}) do
        map("i", picker_action.key, function()
          run_picker_action(picker_action)
        end, {
          desc = picker_action.label,
        })

        map("n", picker_action.key, function()
          run_picker_action(picker_action)
        end, {
          desc = picker_action.label,
        })
      end

      return true
    end,
  }):find()
end

return M
