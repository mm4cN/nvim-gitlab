local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local api = require("gitlab.api")
local glab = require("gitlab.glab")
local yq = require("gitlab.ci.yq")

local function discover(raw_documents, merged_documents)
  local calls = {}
  local inputs, err, vars
  with_mock(glab, "run", function() return "raw yaml", nil end, function()
    with_mock(glab, "run_json", function() return { merged_yaml = "merged yaml" }, nil end, function()
      with_mock(yq, "parse_documents", function(content, opts)
        table.insert(calls, { content = content, cwd = opts.cwd, multiple = opts.multiple })
        if #calls == 1 then return raw_documents or { {} }, nil end
        return merged_documents or { {} }, nil
      end, function()
        inputs, err, vars = api.pipeline_inputs({ project = "ns/proj", ref = "main", cwd = "/repo" })
      end)
    end)
  end)
  return inputs, err, vars, calls
end

describe("yq-backed spec:inputs discovery", function()
  it("passes raw and include-expanded YAML through the generic document adapter", function()
    local inputs, err, vars, calls = discover({ {} }, { {} })
    assert.is_nil(err)
    assert.eq(#inputs, 0)
    assert.eq(#vars, 0)
    assert.eq(#calls, 2)
    assert.eq(calls[1].content, "raw yaml")
    assert.eq(calls[2].content, "merged yaml")
    assert.eq(calls[1].cwd, "/repo")
    assert.eq(calls[1].multiple, true)
  end)

  it("preserves normalized shapes and semantic scalar values", function()
    local inputs = discover({ { spec = { inputs = {
      ["deploy-env"] = {
        type = "string", default = "line one\nline two\n",
        description = "Deployment target\n", options = { "dev", "line one\nline two\n", 42, false },
      },
      count = { type = "number", default = 3 },
    } } } })
    local by_name = {}
    for _, input in ipairs(inputs) do by_name[input.name] = input end
    assert.eq(by_name["deploy-env"].default, "line one\nline two\n")
    assert.eq(by_name["deploy-env"].value, "line one\nline two\n")
    assert.eq(by_name["deploy-env"].description, "Deployment target\n")
    assert.eq(by_name["deploy-env"].options[2], "line one\nline two\n")
    assert.eq(by_name["deploy-env"].options[3], "42")
    assert.eq(by_name["deploy-env"].options[4], "false")
    assert.eq(by_name.count.default, "3")
    assert.eq(by_name.count.value, "3")
  end)

  it("locates spec.inputs across generic YAML documents", function()
    local inputs = discover({
      { metadata = "header" },
      { spec = { inputs = { environment = { default = "staging" } } } },
      { job = { script = "echo ok" } },
    })
    assert.eq(#inputs, 1)
    assert.eq(inputs[1].name, "environment")
    assert.eq(inputs[1].value, "staging")
  end)

  it("returns a yq parsing error without attempting legacy discovery", function()
    local calls = 0
    local inputs, err
    with_mock(glab, "run", function() return "bad yaml", nil end, function()
      with_mock(glab, "run_json", function() return { merged_yaml = "merged" }, nil end, function()
        with_mock(yq, "parse_documents", function()
          calls = calls + 1
          return nil, "yq parse failed"
        end, function()
          inputs, err = api.pipeline_inputs({ project = "ns/proj", ref = "main" })
        end)
      end)
    end)
    assert.is_nil(inputs)
    assert.eq(err, "yq parse failed")
    assert.eq(calls, 1)
  end)

  it("rejects structured values instead of stringifying Lua tables", function()
    local inputs, err = discover({ { spec = { inputs = {
      environment = { type = "string", default = { nested = "value" } },
    } } } })
    assert.is_nil(inputs)
    assert.contains(err, "expected a scalar, got table")
    assert.contains(err, "spec input 'environment' default")
  end)

  it("rejects an empty array where spec.inputs requires a map", function()
    local inputs, err = discover({
      { spec = { inputs = vim.json.decode("[]") } },
    })
    assert.is_nil(inputs)
    assert.eq(err, "Unsupported YAML value for spec.inputs: expected a map")
  end)

  it("rejects an options mapping where a list is required", function()
    local inputs, err = discover({ { spec = { inputs = {
      environment = {
        default = "dev",
        options = { dev = "Development", production = "Production" },
      },
    } } } })
    assert.is_nil(inputs)
    assert.contains(err, "spec input 'environment' options")
    assert.contains(err, "expected a list")
  end)
end)
