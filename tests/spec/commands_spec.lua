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

-- ---------------------------------------------------------------------------
-- Command API: regression guard — these commands must never accept manual IDs.
-- ---------------------------------------------------------------------------

describe("public commands are argument-less", function()
  local commands = {
    "GitlabAuth",
    "GitlabHealth",
    "GitlabCiValidate",
    "GitlabPipelineRun",
    "GitlabPipelineStatus",
    "GitlabPipelineList",
    "GitlabJobList",
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
