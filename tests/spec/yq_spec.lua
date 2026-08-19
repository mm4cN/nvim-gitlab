local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local process = require("gitlab.util.process")
local yq = require("gitlab.ci.yq")

local single_json = [[{"mapping":{"nested":"value"},"array":["one","two"],"multiline":"first line\nsecond line\n","boolean":false,"number":3.5}]]
local multi_json = [[{"name":"first"}
{"name":"second","enabled":true}]]

describe("generic yq YAML-to-JSON adapter", function()
  it("probes single and multi-document preservation with identity-only commands", function()
    yq._reset_probe_cache()
    local calls = 0
    with_mock(process, "run", function(cmd, opts)
      calls = calls + 1
      assert.eq(cmd[1], "yq")
      assert.eq(cmd[#cmd - 1], ".")
      assert.eq(cmd[#cmd], "-")
      assert.not_nil(opts.stdin)
      return calls == 1 and single_json or multi_json, nil
    end, function()
      local ok, err = yq.check()
      assert.eq(ok, true)
      assert.is_nil(err)
      assert.eq(calls, 2)
    end)
  end)

  it("reports missing multi-document capability specifically", function()
    yq._reset_probe_cache()
    with_mock(process, "run", function(_, opts)
      if opts.stdin:find("mapping:", 1, true) then
        return single_json, nil
      end
      return nil, "multiple documents unsupported"
    end, function()
      local ok, err = yq.check()
      assert.is_nil(ok)
      assert.eq(err, "yq YAML-to-JSON multi-document capability is unavailable")
    end)
  end)

  it("negotiates a different compact JSON strategy when the first candidate fails", function()
    yq._reset_probe_cache()
    local calls = 0
    with_mock(process, "run", function(cmd, opts)
      calls = calls + 1
      if cmd[2] == "-c" then
        return nil, "unsupported compact flag"
      end
      if opts.stdin:find("mapping:", 1, true) then return single_json, nil end
      return multi_json, nil
    end, function()
      local ok, err = yq.check()
      assert.eq(ok, true)
      assert.is_nil(err)
      assert.eq(calls, 4)
    end)
  end)

  it("normalizes transcoded output to a document list", function()
    yq._reset_probe_cache()
    local calls = 0
    with_mock(process, "run", function(_, opts)
      calls = calls + 1
      if opts.stdin:find("mapping:", 1, true) then return single_json, nil end
      if opts.stdin:find("name: first", 1, true) then return multi_json, nil end
      return multi_json, nil
    end, function()
      local documents, err = yq.parse_documents("first: doc\n---\nsecond: doc\n", { multiple = true })
      assert.is_nil(err)
      assert.eq(#documents, 2)
      assert.eq(documents[1].name, "first")
      assert.eq(documents[2].enabled, true)
      assert.eq(calls, 2)
    end)
  end)

  it("caches successful single and multi-document strategies", function()
    yq._reset_probe_cache()
    local calls = 0
    with_mock(process, "run", function(_, opts)
      calls = calls + 1
      if opts.stdin:find("mapping:", 1, true) then return single_json, nil end
      return multi_json, nil
    end, function()
      assert.eq(yq.check(), true)
      assert.eq(yq.check(), true)
      assert.eq(calls, 2)
      assert.eq(yq.check({ force = true }), true)
      assert.eq(calls, 4)
    end)
  end)

  it("rejects non-JSON output from a candidate strategy", function()
    yq._reset_probe_cache()
    with_mock(process, "run", function() return "not json", nil end, function()
      local ok, err = yq.check()
      assert.is_nil(ok)
      assert.eq(err, "yq YAML-to-JSON single-document capability is unavailable")
    end)
  end)
end)
