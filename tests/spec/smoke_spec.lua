local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert

describe("smoke", function()
  it("loads gitlab.config without error", function()
    local config = require("gitlab.config")
    assert.not_nil(config)
    assert.not_nil(config.options)
  end)

  it("loads gitlab.git without error", function()
    local git = require("gitlab.git")
    assert.not_nil(git)
  end)

  it("loads gitlab.ci.context without error", function()
    local context = require("gitlab.ci.context")
    assert.not_nil(context)
  end)

  it("loads gitlab.api without error", function()
    local api = require("gitlab.api")
    assert.not_nil(api)
  end)

  it("loads gitlab.glab without error", function()
    local glab = require("gitlab.glab")
    assert.not_nil(glab)
  end)
end)
