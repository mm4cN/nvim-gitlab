-- Stub nui modules so gitlab.ci.pipeline_runner loads without nui installed.
for _, mod in ipairs({ "nui.input", "nui.layout", "nui.popup" }) do
  if not package.loaded[mod] then
    package.preload[mod] = function() return {} end
  end
end

require("gitlab.commands").setup()
local registered = vim.api.nvim_get_commands({})

local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local api = require("gitlab.api")
local git = require("gitlab.git")
local picker = require("gitlab.ui.picker")
local artifacts = require("gitlab.ci.artifacts")

-- ---------------------------------------------------------------------------
-- Command API: regression guard — these commands must never accept manual IDs.
-- ---------------------------------------------------------------------------

describe("public commands are argument-less", function()
  local commands = {
    "GitlabAuth",
    "GitlabHealth",
    "GitlabCiValidate",
    "GitlabPipelineRun",
    "GitlabPipelineList",
    "GitlabPipelineStatus",
    "GitlabPipelineDetails",
    "GitlabJobList",
    "GitlabJobRetry",
    "GitlabJobLogs",
    "GitlabJobDetails",
    "GitlabJobArtifacts",
  }

  it("registers the intentional command set without arguments", function()
    local count = 0
    for name, command in pairs(registered) do
      if name:match("^Gitlab") then
        count = count + 1
        assert.eq(command.nargs, "0")
      end
    end
    assert.eq(count, #commands)
    for _, name in ipairs(commands) do
      assert.eq(registered[name] ~= nil, true)
    end
  end)
end)

describe("pipeline runner command", function()
  it("registers the interactive runner as GitlabPipelineRun", function()
    assert.eq(registered.GitlabPipelineRun ~= nil, true)
    assert.eq(registered.GitlabPipelineRun.nargs, "0")
  end)

  it("does not register GitlabPipelineRunProject", function()
    assert.eq(registered.GitlabPipelineRunProject, nil)
  end)
end)

-- ---------------------------------------------------------------------------
-- artifacts.pick_and_download
-- ---------------------------------------------------------------------------

local function with_context(fn)
  with_mock(git, "root", function()
    return "/repo", nil
  end, function()
    with_mock(git, "branch", function()
      return "main", nil
    end, fn)
  end)
end

describe("artifacts.pick_and_download", function()
  it("presents a job picker", function()
    local picker_called = false

    with_context(function()
      with_mock(api, "latest_pipeline", function()
        return { id = 42 }, nil
      end, function()
        with_mock(api, "pipeline_jobs", function()
          return { { id = 1, name = "build", status = "success" } }, nil
        end, function()
          with_mock(picker, "select", function(_items, _opts, _cb)
            picker_called = true
          end, function()
            artifacts.pick_and_download()
          end)
        end)
      end)
    end)

    assert.eq(picker_called, true)
  end)

  it("passes all pipeline jobs to the picker", function()
    local received

    with_context(function()
      with_mock(api, "latest_pipeline", function()
        return { id = 42 }, nil
      end, function()
        with_mock(api, "pipeline_jobs", function()
          return {
            { id = 1, name = "build", status = "success" },
            { id = 2, name = "test",  status = "failed" },
          }, nil
        end, function()
          with_mock(picker, "select", function(items, _opts, _cb)
            received = items
          end, function()
            artifacts.pick_and_download()
          end)
        end)
      end)
    end)

    assert.eq(#received, 2)
    assert.eq(received[1].id, 1)
    assert.eq(received[2].id, 2)
  end)

  it("calls download with the selected job id and resolved root", function()
    local download_opts

    with_context(function()
      with_mock(api, "latest_pipeline", function()
        return { id = 42 }, nil
      end, function()
        with_mock(api, "pipeline_jobs", function()
          return { { id = 7, name = "deploy", status = "success" } }, nil
        end, function()
          with_mock(picker, "select", function(items, _opts, cb)
            cb(items[1])
          end, function()
            with_mock(artifacts, "download", function(opts)
              download_opts = opts
            end, function()
              artifacts.pick_and_download()
            end)
          end)
        end)
      end)
    end)

    assert.eq(download_opts.job_id, 7)
    assert.eq(download_opts.root, "/repo")
  end)

  it("does not open picker when pipeline fetch fails", function()
    local picker_called = false

    with_context(function()
      with_mock(api, "latest_pipeline", function()
        return nil, "not found"
      end, function()
        with_mock(picker, "select", function()
          picker_called = true
        end, function()
          artifacts.pick_and_download()
        end)
      end)
    end)

    assert.eq(picker_called, false)
  end)

  it("does not open picker when the pipeline has no jobs", function()
    local picker_called = false

    with_context(function()
      with_mock(api, "latest_pipeline", function()
        return { id = 42 }, nil
      end, function()
        with_mock(api, "pipeline_jobs", function()
          return {}, nil
        end, function()
          with_mock(picker, "select", function()
            picker_called = true
          end, function()
            artifacts.pick_and_download()
          end)
        end)
      end)
    end)

    assert.eq(picker_called, false)
  end)
end)
