local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local telescope_actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local format = require("gitlab.ci.format")

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

local function jobs_picker(opts, title, attach_mappings)
  local pipeline = opts.pipeline
  local jobs = opts.jobs

  local previewer = previewers.new_buffer_previewer({
    title = "Details",
    define_preview = function(self, entry)
      local job = entry and entry.value
      local lines = {
        "Pipeline #" .. tostring(pipeline.id),
        "Ref:    " .. format.value(pipeline.ref),
        "Status: " .. format.status_icon(pipeline.status) .. " " .. format.value(pipeline.status),
        "",
      }
      if job then
        vim.list_extend(lines, format.job_preview(job))
      end
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
    end,
  })

  pickers.new({
    layout_strategy = "horizontal",
    layout_config = {
      width = 0.9,
      height = math.min(#jobs + 6, 18),
      preview_width = 0.4,
    },
  }, {
    prompt_title = title,
    results_title = "Jobs",
    previewer = previewer,

    finder = finders.new_table({
      results = jobs,
      entry_maker = function(job)
        local display = format.job(job)
        return { value = job, display = display, ordinal = display }
      end,
    }),

    sorter = conf.generic_sorter({}),
    attach_mappings = attach_mappings,
  }):find()
end

function M.show_pipeline(opts)
  local pipeline = opts.pipeline

  jobs_picker(opts, "Pipeline #" .. tostring(pipeline.id) .. " — Jobs", function(prompt_bufnr, map)
    local function selected_job()
      local entry = action_state.get_selected_entry()
      return entry and entry.value or nil
    end

    local function close_and(fn)
      return function()
        local job = selected_job()
        telescope_actions.close(prompt_bufnr)
        fn(job)
      end
    end

    telescope_actions.select_default:replace(close_and(function(job)
      if job then opts.actions.details(job) end
    end))

    map({ "i", "n" }, "<C-l>", close_and(function(job)
      if job then opts.actions.logs(job) end
    end), { desc = "Logs" })

    map({ "i", "n" }, "<C-a>", close_and(function(job)
      if job then opts.actions.artifacts(job) end
    end), { desc = "Artifacts" })

    map({ "i", "n" }, "<C-r>", function()
      telescope_actions.close(prompt_bufnr)
      opts.actions.rerun()
    end, { desc = "Re-run pipeline" })

    map("n", "r", function()
      telescope_actions.close(prompt_bufnr)
      opts.actions.refresh()
    end, { desc = "Refresh" })

    map({ "i", "n" }, "<C-b>", function()
      telescope_actions.close(prompt_bufnr)
      if opts.on_back then opts.on_back() end
    end, { desc = "Back" })

    return true
  end)
end

function M.show_jobs(opts)
  local pipeline = opts.pipeline

  jobs_picker(opts, "Jobs — Pipeline #" .. tostring(pipeline.id), function(prompt_bufnr, map)
    local function selected_job()
      local entry = action_state.get_selected_entry()
      return entry and entry.value or nil
    end

    local function close_and(fn)
      return function()
        local job = selected_job()
        telescope_actions.close(prompt_bufnr)
        fn(job)
      end
    end

    telescope_actions.select_default:replace(close_and(function(job)
      if job then opts.actions.details(job) end
    end))

    map({ "i", "n" }, "<C-l>", close_and(function(job)
      if job then opts.actions.logs(job) end
    end), { desc = "Logs" })

    map({ "i", "n" }, "<C-a>", close_and(function(job)
      if job then opts.actions.artifacts(job) end
    end), { desc = "Artifacts" })

    map({ "i", "n" }, "<C-r>", close_and(function(job)
      if job then opts.actions.retry(job) end
    end), { desc = "Retry job" })

    map({ "i", "n" }, "<C-p>", close_and(function(job)
      if job then opts.actions.play(job) end
    end), { desc = "Play job" })

    map("n", "r", function()
      telescope_actions.close(prompt_bufnr)
      opts.actions.refresh()
    end, { desc = "Refresh" })

    map({ "i", "n" }, "<C-b>", function()
      telescope_actions.close(prompt_bufnr)
      if opts.on_back then opts.on_back() end
    end, { desc = "Back" })

    return true
  end)
end

function M.show_job(opts)
  local job = opts.job
  local commit = job.commit or {}
  local pipeline_ctx = job.pipeline or {}

  local previewer = previewers.new_buffer_previewer({
    title = "Job Details",
    define_preview = function(self, _entry)
      local lines = {
        "Job #" .. tostring(job.id),
        "",
        "Name:      " .. format.value(job.name),
        "Status:    " .. format.status_icon(job.status) .. " " .. format.value(job.status),
        "Stage:     " .. format.value(job.stage),
        "Ref:       " .. format.value(job.ref),
        "Duration:  " .. format.duration(job.duration),
        "Started:   " .. format.value(job.started_at),
        "Finished:  " .. format.value(job.finished_at),
        "",
        "Pipeline:",
        "  ID:      " .. format.value(pipeline_ctx.id),
        "  Status:  " .. format.status_icon(pipeline_ctx.status) .. " " .. format.value(pipeline_ctx.status),
        "  Ref:     " .. format.value(pipeline_ctx.ref),
        "",
        "Commit:",
        "  SHA:     " .. format.short_sha(commit.id or commit.sha),
        "  Title:   " .. format.value(commit.title),
        "  Author:  " .. format.value(commit.author_name),
      }
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
    end,
  })

  pickers.new({
    layout_strategy = "horizontal",
    layout_config = { width = 0.9, height = 8, preview_width = 0.6 },
  }, {
    prompt_title = "Job #" .. tostring(job.id),
    results_title = "Job",
    previewer = previewer,

    finder = finders.new_table({
      results = { job },
      entry_maker = function(j)
        local display = format.job(j)
        return { value = j, display = display, ordinal = display }
      end,
    }),

    sorter = conf.generic_sorter({}),

    attach_mappings = function(prompt_bufnr, map)
      telescope_actions.select_default:replace(function()
        telescope_actions.close(prompt_bufnr)
        opts.actions.logs()
      end)

      map({ "i", "n" }, "<C-r>", function()
        telescope_actions.close(prompt_bufnr)
        opts.actions.retry()
      end, { desc = "Retry job" })

      map({ "i", "n" }, "<C-a>", function()
        telescope_actions.close(prompt_bufnr)
        opts.actions.artifacts()
      end, { desc = "Artifacts" })

      map({ "i", "n" }, "<C-p>", function()
        telescope_actions.close(prompt_bufnr)
        opts.actions.play()
      end, { desc = "Play job" })

      map("n", "r", function()
        telescope_actions.close(prompt_bufnr)
        opts.actions.refresh()
      end, { desc = "Refresh" })

      map({ "i", "n" }, "<C-b>", function()
        telescope_actions.close(prompt_bufnr)
        if opts.on_back then opts.on_back() end
      end, { desc = "Back" })

      return true
    end,
  }):find()
end

return M
