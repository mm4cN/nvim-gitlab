local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert

local process = require("gitlab.util.process")

describe("process stdin forwarding", function()
  it("passes run_json opts.stdin through run to the child process", function()
    local result, err = process.run_json({
      "sh",
      "-c",
      [[IFS= read -r value; printf '{"value":"%s"}' "$value"]],
    }, {
      stdin = "forwarded through vim.system\n",
    })

    assert.is_nil(err)
    assert.eq(result.value, "forwarded through vim.system")
  end)
end)
