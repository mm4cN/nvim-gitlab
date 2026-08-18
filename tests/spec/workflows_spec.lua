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

  it("opens the current pipeline job list", function()
    local shown
    local pipeline = { id = 7, ref = "main" }
    local pipeline_jobs = { { id = 8, name = "test", status = "success" } }
    with_mocks({
      { git, "root", function() return "/repo", nil end },
      { git, "branch", function() return "main", nil end },
      { api, "latest_pipeline", function() return pipeline, nil end },
      { api, "pipeline_jobs", function() return pipeline_jobs, nil end },
      { picker, "show_jobs", function(opts) shown = opts end },
    }, function()
      jobs.list()
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
