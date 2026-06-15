local M = {}

function M.select(items, opts, callback)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    error("telescope.nvim is not installed")
  end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = opts.prompt or "Select",
    finder = finders.new_table({
      results = items,
      entry_maker = function(item)
        return {
          value = item,
          display = opts.format_item and opts.format_item(item) or tostring(item),
          ordinal = opts.format_item and opts.format_item(item) or tostring(item),
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()

        actions.close(prompt_bufnr)

        if callback then
          callback(selection.value)
        end
      end)

      return true
    end,
  }):find()
end

return M
