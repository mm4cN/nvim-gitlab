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
local pipelines = require("gitlab.ci.pipelines")
local process = require("gitlab.util.process")
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
  end
end)

describe("pipeline and job workflows", function()
  it("loads 100 recent pipelines for local picker filtering", function()
    local requested
    with_mocks({
      { git, "root", function() return "/repo", nil end },
      { api, "pipelines", function(opts) requested = opts return {}, nil end },
    }, function()
      details.show()
    end)
    assert.eq(requested.per_page, 100)
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
end)
