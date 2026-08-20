local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local actions = require("gitlab.ci.actions")
local api = require("gitlab.api")
local artifacts = require("gitlab.ci.artifacts")
local auth = require("gitlab.auth")
local buffer = require("gitlab.ui.buffer")
local config = require("gitlab.config")
local details = require("gitlab.ci.details")
local git = require("gitlab.git")
local job_details = require("gitlab.ci.job_details")
local jobs = require("gitlab.ci.jobs")
local log_buffer = require("gitlab.ci.log_buffer")
local picker = require("gitlab.ui.picker")
local pipeline_watch = require("gitlab.ci.pipeline_watch")
local pipelines = require("gitlab.ci.pipelines")
local process = require("gitlab.util.process")
local project_picker = require("gitlab.ui.project_picker")
local ui_state = require("gitlab.ui.state")

local function with_mocks(mocks, fn, index)
  index = index or 1
  local mock = mocks[index]
  if not mock then
    fn()
    return
  end
  with_mock(mock[1], mock[2], mock[3], function()
    with_mocks(mocks, fn, index + 1)
  end)
end

local function with_picker_backend(name, backend, fn)
  local module_name = "gitlab.ui.pickers." .. name
  local old_picker = config.options.picker
  local old_backend = package.loaded[module_name]
  config.options.picker = name
  package.loaded[module_name] = backend
  local ok, err = pcall(fn)
  config.options.picker = old_picker
  package.loaded[module_name] = old_backend
  if not ok then error(err) end
end

describe("job actions", function()
  for _, case in ipairs({
    { name = "retry", fn = actions.retry_job, suffix = "/retry" },
    { name = "play", fn = actions.play_job, suffix = "/play" },
  }) do
    it("sends the " .. case.name .. " request", function()
      local request_path, request_opts
      with_mocks({
        { git, "root", function() return "/repo", nil end },
        { api, "request", function(path, opts)
          request_path, request_opts = path, opts
          return {}, nil
        end },
        { buffer, "refresh", function() end },
      }, function()
        case.fn(42)
      end)
      assert.eq(request_path, "projects/:id/jobs/42" .. case.suffix)
      assert.eq(request_opts.method, "POST")
      assert.eq(request_opts.cwd, "/repo")
    end)

    it("encodes every namespace level for a cross-project " .. case.name .. " request", function()
      local request_path
      with_mocks({
        { api, "request", function(path)
          request_path = path
          return {}, nil
        end },
        { buffer, "refresh", function() end },
      }, function()
        case.fn(42, { root = "/repo", project = "group/subgroup/project" })
      end)
      assert.eq(request_path, "projects/group%2Fsubgroup%2Fproject/jobs/42" .. case.suffix)
    end)
  end
end)

describe("pipeline and job workflows", function()
  it("loads 100 recent pipelines for local picker filtering", function()
    local requested
    with_mocks({
      { git, "root", function() return "/repo", nil end },
      { api, "pipelines", function(opts) requested = opts return {}, nil end },
      { project_picker, "select", function(_, callback) callback(nil) end },
    }, function()
      details.show()
    end)
    assert.eq(requested.per_page, 100)
  end)

  it("switches PipelineList projects and filters 100 pipelines under the selected project", function()
    local requested = {}
    local picker_calls = {}
    local shown
    local current_pipeline = { id = 1, ref = "main", status = "success" }
    local selected_pipeline = { id = 2, ref = "trunk", status = "running" }
    with_mocks({
      { git, "root", function() return "/repo", nil end },
      { git, "remote_project", function() return "current/project", nil end },
      { api, "pipelines", function(opts)
        table.insert(requested, opts)
        return opts.project == "selected/project" and { selected_pipeline } or { current_pipeline }, nil
      end },
      { picker, "select", function(items, opts, callback)
        table.insert(picker_calls, { items = items, opts = opts, callback = callback })
      end },
      { project_picker, "select", function(_, callback)
        callback({ path_with_namespace = "selected/project", default_branch = "trunk" })
      end },
      { api, "pipeline_jobs", function(_, opts)
        assert.eq(opts.project, "selected/project")
        return {}, nil
      end },
      { picker, "show_pipeline", function(opts) shown = opts end },
      { pipeline_watch, "watch", function() return true end },
    }, function()
      details.show()
      assert.contains(picker_calls[1].opts.prompt, "current/project")
      -- Find the project picker action (it has key <C-p>)
      local project_action
      for _, action in ipairs(picker_calls[1].opts.actions) do
        if action.key == "<C-p>" then
          project_action = action
          break
        end
      end
      assert.not_nil(project_action)
      project_action.callback(current_pipeline)
      assert.contains(picker_calls[2].opts.prompt, "selected/project")
      picker_calls[2].callback(selected_pipeline)
    end)
    assert.eq(#requested, 2)
    assert.eq(requested[1].project, "current/project")
    assert.eq(requested[2].project, "selected/project")
    assert.eq(requested[1].per_page, 100)
    assert.eq(requested[2].per_page, 100)
    assert.eq(shown.pipeline, selected_pipeline)
  end)

  it("<C-w> watches the selected pipeline under a cross-project <C-p> selection", function()
    local picker_calls = {}
    local watch_calls = {}
    local current_pipeline = { id = 1, ref = "main", status = "success" }
    local selected_pipeline = { id = 99, ref = "trunk", status = "running" }
    with_mocks({
      { git, "root", function() return "/repo", nil end },
      { git, "remote_project", function() return "current/project", nil end },
      { api, "pipelines", function(opts)
        return opts.project == "selected/project" and { selected_pipeline } or { current_pipeline }, nil
      end },
      { picker, "select", function(items, opts, callback)
        table.insert(picker_calls, { items = items, opts = opts, callback = callback })
      end },
      { project_picker, "select", function(_, callback)
        callback({ path_with_namespace = "selected/project", default_branch = "trunk" })
      end },
      { pipeline_watch, "watch", function(opts)
        table.insert(watch_calls, opts)
        return true
      end },
    }, function()
      details.show()
      -- Switch to the foreign project via <C-p>, mirroring
      -- "GitlabPipelineList -> C-p -> foreign/project -> C-w on pipeline".
      local project_action
      for _, action in ipairs(picker_calls[1].opts.actions) do
        if action.key == "<C-p>" then
          project_action = action
          break
        end
      end
      assert.not_nil(project_action)
      project_action.callback(current_pipeline)

      -- Now trigger <C-w> on the picker showing "selected/project".
      local watch_action
      for _, action in ipairs(picker_calls[2].opts.actions) do
        if action.key == "<C-w>" then
          watch_action = action
          break
        end
      end
      assert.not_nil(watch_action)
      watch_action.callback(selected_pipeline)
    end)

    assert.eq(#watch_calls, 1)
    assert.eq(watch_calls[1].pipeline_id, 99)
    assert.eq(watch_calls[1].project, "selected/project")
    assert.eq(watch_calls[1].root, "/repo")
  end)

  it("duplicate <C-w> watch actions on the same pipeline create no duplicate timer or notification", function()
    -- Exercises the real pipeline_watch module (not mocked) through the
    -- picker action, so this covers the actual idempotency guarantee rather
    -- than just the wiring.
    local notification = require("gitlab.ui.notification")
    local picker_calls = {}
    local pipeline = { id = 5, ref = "main", status = "running" }

    local timers_created = 0
    local fake_timer
    local function make_fake_timer()
      local callback, running = nil, false
      local t = { stopped = false, closed = false }
      function t:start(_, _, cb) callback = cb; running = true end
      function t:stop() self.stopped = true; running = false end
      function t:close() self.closed = true end
      function t:is_closing() return self.closed end
      function t:fire() if running and callback then callback() end end
      return t
    end

    local info_calls = {}
    pipeline_watch._set_schedule_wrap(function(fn) return fn end)
    pipeline_watch._set_timer_constructor(function()
      timers_created = timers_created + 1
      fake_timer = make_fake_timer()
      return fake_timer
    end)

    local ok, err = pcall(function()
      with_mock(notification, "info", function(msg) table.insert(info_calls, msg) end, function()
        with_mocks({
          { git, "root", function() return "/repo", nil end },
          { git, "remote_project", function() return "current/project", nil end },
          { api, "pipelines", function() return { pipeline }, nil end },
          { api, "pipeline", function(_, opts)
            return { id = pipeline.id, ref = pipeline.ref, status = "success", project = opts.project }, nil
          end },
          { picker, "select", function(items, opts, callback)
            table.insert(picker_calls, { items = items, opts = opts, callback = callback })
          end },
        }, function()
          details.show()
          local watch_action
          for _, action in ipairs(picker_calls[1].opts.actions) do
            if action.key == "<C-w>" then
              watch_action = action
              break
            end
          end
          assert.not_nil(watch_action)

          -- First <C-w> starts the watcher; the duplicate call must be a no-op
          -- because pipeline_watch.watch() is idempotent per project+pipeline_id.
          -- (The picker action itself acknowledges each keypress with a
          -- "Watching pipeline #N" info message — that per-keypress UI
          -- acknowledgment is not the completion notification under test.)
          watch_action.callback(pipeline)
          watch_action.callback(pipeline)

          assert.eq(timers_created, 1)

          -- Drive the single timer to terminal state and confirm exactly one
          -- completion notification is emitted — not two.
          fake_timer:fire()

          local completion_notifications = 0
          for _, msg in ipairs(info_calls) do
            if msg:find("success", 1, true) then
              completion_notifications = completion_notifications + 1
            end
          end
          assert.eq(completion_notifications, 1)
        end)
      end)
    end)

    pipeline_watch._reset_test_overrides()
    pipeline_watch.stop(pipeline.id, "current/project")
    if not ok then error(err, 0) end
  end)

  it("reopens the current PipelineList project when project selection is cancelled", function()
    local requested = {}
    local picker_calls = {}
    with_mocks({
      { git, "root", function() return "/repo", nil end },
      { git, "remote_project", function() return "current/project", nil end },
      { api, "pipelines", function(opts)
        table.insert(requested, opts.project)
        return { { id = 1, ref = "main", status = "success" } }, nil
      end },
      { picker, "select", function(_, opts)
        table.insert(picker_calls, opts)
      end },
      { project_picker, "select", function(_, callback) callback(nil) end },
      { pipeline_watch, "watch", function() return true end },
    }, function()
      details.show()
      -- Find the project picker action
      local project_action
      for _, action in ipairs(picker_calls[1].actions) do
        if action.key == "<C-p>" then
          project_action = action
          break
        end
      end
      assert.not_nil(project_action)
      project_action.callback()
    end)
    assert.eq(#requested, 2)
    assert.eq(requested[1], "current/project")
    assert.eq(requested[2], "current/project")
  end)

  it("can switch projects again when the selected project has no pipelines", function()
    local requested = {}
    local picker_calls = {}
    local project_callbacks = {}
    with_mocks({
      { git, "root", function() return "/repo", nil end },
      { git, "remote_project", function() return "current/project", nil end },
      { api, "pipelines", function(opts)
        table.insert(requested, opts.project)
        if opts.project == "empty/project" then return {}, nil end
        return { { id = 1, ref = "main", status = "success" } }, nil
      end },
      { picker, "select", function(_, opts) table.insert(picker_calls, opts) end },
      { project_picker, "select", function(_, callback) table.insert(project_callbacks, callback) end },
      { pipeline_watch, "watch", function() return true end },
    }, function()
      details.show()
      -- Find the project picker action
      local project_action
      for _, action in ipairs(picker_calls[1].actions) do
        if action.key == "<C-p>" then
          project_action = action
          break
        end
      end
      assert.not_nil(project_action)
      project_action.callback()
      project_callbacks[1]({ path_with_namespace = "empty/project" })
      project_callbacks[2]({ path_with_namespace = "next/project" })
    end)
    assert.eq(#requested, 3)
    assert.eq(requested[1], "current/project")
    assert.eq(requested[2], "empty/project")
    assert.eq(requested[3], "next/project")
    assert.contains(picker_calls[2].prompt, "next/project")
  end)

  it("keeps selected-project context in pipeline detail actions", function()
    local shown
    local called = {}
    local pipeline = { id = 7, ref = "trunk", status = "success" }
    local job = { id = 8, name = "test", status = "success" }
    with_mocks({
      { git, "root", function() return "/repo", nil end },
      { api, "pipelines", function() return { pipeline }, nil end },
      { picker, "select", function(items, _, callback) callback(items[1]) end },
      { api, "pipeline_jobs", function(_, opts)
        called.jobs_project = opts.project
        return { job }, nil
      end },
      { picker, "show_pipeline", function(opts) shown = opts end },
    }, function()
      details.show({ project = "selected/project" })
    end)
    with_mocks({
      { jobs, "logs", function(opts) called.logs_project = opts.project end },
      { artifacts, "download", function(opts) called.artifacts_project = opts.project end },
      { actions, "rerun_pipeline", function(_, opts) called.rerun_project = opts.project end },
      { api, "pipeline", function(_, opts)
        called.refresh_pipeline_project = opts.project
        return pipeline, nil
      end },
      { api, "pipeline_jobs", function(_, opts)
        called.refresh_jobs_project = opts.project
        return { job }, nil
      end },
      { api, "job", function(_, opts)
        called.job_project = opts.project
        return job, nil
      end },
      { job_details, "show", function(opts) called.job_details_project = opts.project end },
    }, function()
      shown.actions.logs(job)
      shown.actions.artifacts(job)
      shown.actions.rerun()
      shown.actions.refresh()
      shown.actions.details(job)
    end)
    assert.eq(called.jobs_project, "selected/project")
    assert.eq(called.logs_project, "selected/project")
    assert.eq(called.artifacts_project, "selected/project")
    assert.eq(called.rerun_project, "selected/project")
    assert.eq(called.refresh_pipeline_project, "selected/project")
    assert.eq(called.refresh_jobs_project, "selected/project")
    assert.eq(called.job_project, "selected/project")
    assert.eq(called.job_details_project, "selected/project")
  end)

  for _, backend_name in ipairs({ "vim_ui", "telescope" }) do
    it("runs GitlabPipelineList through " .. backend_name, function()
      local shown
      local pipeline = { id = 7, ref = "main", status = "success" }
      local pipeline_jobs = { { id = 8, name = "test", status = "success" } }
      with_picker_backend(backend_name, {
        select = function(items, _, callback) callback(items[1]) end,
        show_pipeline = function(opts) shown = opts end,
      }, function()
        with_mocks({
          { git, "root", function() return "/repo", nil end },
          { api, "pipelines", function() return { pipeline }, nil end },
          { api, "pipeline_jobs", function() return pipeline_jobs, nil end },
        }, function()
          vim.cmd("GitlabPipelineList")
        end)
      end)
      assert.eq(shown.pipeline, pipeline)
      assert.eq(shown.jobs, pipeline_jobs)
    end)

    it("runs GitlabJobList through " .. backend_name, function()
      local shown
      local selected = { id = 8, name = "test", status = "manual" }
      local full_job = { id = 8, name = "test", status = "manual", pipeline = { id = 7 } }
      with_picker_backend(backend_name, {
        select = function(items, _, callback) callback(items[1]) end,
        show_job = function(opts) shown = opts end,
      }, function()
        with_mocks({
          { git, "root", function() return "/repo", nil end },
          { git, "branch", function() return "main", nil end },
          { api, "latest_pipeline", function() return { id = 7 }, nil end },
          { api, "pipeline_jobs", function() return { selected }, nil end },
          { api, "job", function() return full_job, nil end },
        }, function()
          vim.cmd("GitlabJobList")
        end)
      end)
      assert.eq(shown.job, full_job)
    end)
  end

  it("opens selected pipeline details with its jobs", function()
    local shown
    local pipeline = { id = 7, ref = "main", status = "success" }
    local pipeline_jobs = { { id = 8, name = "test", status = "success" } }
    with_mocks({
      { git, "root", function() return "/repo", nil end },
      { api, "pipelines", function() return { pipeline }, nil end },
      { picker, "select", function(items, _, callback) callback(items[1]) end },
      { api, "pipeline_jobs", function() return pipeline_jobs, nil end },
      { picker, "show_pipeline", function(opts) shown = opts end },
    }, function()
      details.show()
    end)
    assert.eq(shown.pipeline, pipeline)
    assert.eq(shown.jobs, pipeline_jobs)
  end)

  it("opens a pre-fetched job detail", function()
    local shown
    local job = { id = 8, name = "test", status = "manual" }
    with_mock(picker, "show_job", function(opts) shown = opts end, function()
      job_details.show({ job = job, root = "/repo" })
    end)
    assert.eq(shown.job, job)
  end)

  it("navigates from pipeline details to job details", function()
    local pipeline_view, job_view
    local pipeline = { id = 7, ref = "main", status = "success" }
    local listed_job = { id = 8, name = "test", status = "manual" }
    local full_job = { id = 8, name = "test", status = "manual", pipeline = { id = 7 } }
    with_mocks({
      { git, "root", function() return "/repo", nil end },
      { api, "pipelines", function() return { pipeline }, nil end },
      { picker, "select", function(items, _, callback) callback(items[1]) end },
      { api, "pipeline_jobs", function() return { listed_job }, nil end },
      { picker, "show_pipeline", function(opts) pipeline_view = opts end },
      { api, "job", function() return full_job, nil end },
      { picker, "show_job", function(opts) job_view = opts end },
    }, function()
      details.show()
      pipeline_view.actions.details(listed_job)
    end)
    assert.eq(job_view.job, full_job)
    assert.truthy(job_view.on_back)
  end)

  it("keeps all job detail actions reachable", function()
    local shown, called = nil, {}
    local job = { id = 8, name = "deploy", status = "manual" }
    with_mock(picker, "show_job", function(opts) shown = opts end, function()
      job_details.show({ job = job, root = "/repo" })
    end)
    with_mocks({
      { jobs, "logs", function(opts) called.logs = opts.args end },
      { actions, "retry_job", function(id) called.retry = id end },
      { artifacts, "download", function(opts) called.artifacts = opts.job_id end },
      { actions, "play_job", function(id) called.play = id end },
    }, function()
      shown.actions.logs()
      shown.actions.retry()
      shown.actions.artifacts()
      shown.actions.play()
    end)
    assert.eq(called.logs, 8)
    assert.eq(called.retry, 8)
    assert.eq(called.artifacts, 8)
    assert.eq(called.play, 8)
  end)

  it("clears the manual play mapping when the next view does not define it", function()
    buffer.show({ title = "Manual Job", lines = {}, keymaps = { P = function() end } })
    assert.eq(vim.fn.maparg("P", "n", false, true).buffer, 1)
    buffer.replace({ title = "Non-manual Job", lines = {}, keymaps = {} })
    assert.eq(vim.fn.maparg("P", "n", false, true).buffer, nil)
    buffer.close_current()
    assert.eq(ui_state.buf, nil)
  end)

  it("renders current pipeline status", function()
    local shown
    with_mocks({
      { git, "root", function() return "/repo", nil end },
      { git, "branch", function() return "main", nil end },
      { api, "pipelines", function() return { { id = 7, ref = "main", status = "success" } }, nil end },
      { buffer, "show", function(view) shown = view end },
    }, function()
      pipelines.status()
    end)
    assert.eq(shown.title, "GitLab Pipeline Status")
    assert.contains(table.concat(shown.lines, "\n"), "#7")
  end)
end)

describe("logs and artifacts", function()
  it("reuses the named log buffer for the same job", function()
    local first = log_buffer.create_or_update(42, { "first" })
    local second = log_buffer.create_or_update(42, { "second" })
    local lines = vim.api.nvim_buf_get_lines(second, 0, -1, false)
    local ok, err = pcall(function()
      assert.eq(second, first)
      assert.eq(lines[1], "second")
    end)
    vim.api.nvim_buf_delete(second, { force = true })
    if not ok then error(err) end
  end)

  it("downloads an artifact archive to the requested output directory", function()
    local command, pushed
    local old_extract = config.options.extract_artifacts
    config.options.extract_artifacts = false
    local ok, err = pcall(function()
      with_mocks({
        { auth, "token", function() return "token", nil end },
        { api, "get", function() return { id = 99 }, nil end },
        { vim.fn, "isdirectory", function() return 1 end },
        { process, "run", function(cmd) command = cmd; return "", nil end },
        { buffer, "push", function(view) pushed = view end },
      }, function()
        artifacts.download({ job_id = 42, root = "/repo", output_dir = "/artifacts" })
      end)
      assert.eq(command[1], "curl")
      assert.eq(command[#command - 1], "--output")
      assert.eq(command[#command], "/artifacts/job-42-artifacts.zip")
      assert.contains(table.concat(command, "\n"), "/projects/99/jobs/42/artifacts")
      assert.eq(pushed.title, "GitLab Artifacts")
    end)
    config.options.extract_artifacts = old_extract
    if not ok then error(err) end
  end)

  it("encodes every namespace level for cross-project artifact lookup", function()
    local project_path
    local old_extract = config.options.extract_artifacts
    config.options.extract_artifacts = false
    local ok, err = pcall(function()
      with_mocks({
        { auth, "token", function() return "token", nil end },
        { api, "get", function(path)
          project_path = path
          return { id = 99 }, nil
        end },
        { vim.fn, "isdirectory", function() return 1 end },
        { process, "run", function() return "", nil end },
        { buffer, "push", function() end },
      }, function()
        artifacts.download({
          job_id = 42,
          root = "/repo",
          project = "group/subgroup/project",
          output_dir = "/artifacts",
        })
      end)
      assert.eq(project_path, "projects/group%2Fsubgroup%2Fproject")
    end)
    config.options.extract_artifacts = old_extract
    if not ok then error(err) end
  end)
end)
