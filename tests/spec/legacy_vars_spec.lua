local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local api = require("gitlab.api")
local glab = require("gitlab.glab")
local yq = require("gitlab.ci.yq")
local pipeline_runner = require("gitlab.ci.pipeline_runner")

local function discover_legacy(decoded)
  local vars, discovery_err
  with_mock(glab, "run", function() return "raw yaml", nil end, function()
    with_mock(glab, "run_json", function() return { merged_yaml = "merged yaml" }, nil end, function()
      local call = 0
      with_mock(yq, "parse_documents", function()
        call = call + 1
        return call == 1 and { {} } or { { variables = decoded } }, nil
      end, function()
        local _, err, result = api.pipeline_inputs({ project = "ns/proj", ref = "main" })
        vars = result
        discovery_err = err
      end)
    end)
  end)
  return vars, discovery_err
end

describe("yq-backed legacy described variables", function()
  it("keeps only map entries with value and a non-empty description", function()
    local vars = discover_legacy({
      ENV = { value = "staging", description = "Target environment" },
      EMPTY_DESC = { value = "x", description = "" },
      NO_VALUE = { description = "Only a description" },
    })
    assert.eq(#vars, 1)
    assert.eq(vars[1].key, "ENV")
    assert.eq(vars[1].value, "staging")
    assert.eq(vars[1].description, "Target environment")
  end)

  it("preserves multiline strings and normalizes non-string scalars", function()
    local vars = discover_legacy({
      NOTES = { value = "first\nsecond\n", description = "Long\ndescription\n" },
      COUNT = { value = 12, description = "Count" },
      ENABLED = { value = false, description = "Flag" },
    })
    local by_key = {}
    for _, var in ipairs(vars) do by_key[var.key] = var end
    assert.eq(by_key.NOTES.value, "first\nsecond\n")
    assert.eq(by_key.NOTES.description, "Long\ndescription\n")
    assert.eq(by_key.COUNT.value, "12")
    assert.eq(by_key.ENABLED.value, "false")
  end)

  it("preserves options in the normalized result", function()
    local vars = discover_legacy({
      ENV = {
        value = "staging", description = "Target environment",
        options = { "dev", "staging", 3, false },
      },
    })
    assert.eq(#vars[1].options, 4)
    assert.eq(vars[1].options[1], "dev")
    assert.eq(vars[1].options[3], "3")
    assert.eq(vars[1].options[4], "false")
  end)

  it("rejects structured values instead of leaking table addresses", function()
    local vars, err = discover_legacy({
      ENV = { value = { nested = "value" }, description = "Target" },
    })
    assert.is_nil(vars)
    assert.contains(err, "legacy variable 'ENV' value")
    assert.contains(err, "expected a scalar, got table")
  end)

  it("rejects an empty array where variables requires a map", function()
    local vars, err = discover_legacy(vim.json.decode("[]"))
    assert.is_nil(vars)
    assert.eq(err, "Unsupported YAML value for variables: expected a map")
  end)

  it("rejects an options mapping where a list is required", function()
    local vars, err = discover_legacy({
      ENV = {
        value = "staging",
        description = "Target environment",
        options = { dev = "Development", staging = "Staging" },
      },
    })
    assert.is_nil(vars)
    assert.contains(err, "legacy variable 'ENV' options")
    assert.contains(err, "expected a list")
  end)
end)

describe("fetch_inputs state preservation", function()
  it("preserves edits for the same project and ref", function()
    with_mock(api, "pipeline_inputs", function()
      return {}, nil, { { key = "ENV", value = "staging", description = "Target" } }
    end, function()
      local state = { project = "ns/proj", ref = "main", fields = {}, yaml_vars = {}, yaml_vars_key = "" }
      pipeline_runner._fetch_inputs(state)
      state.yaml_vars[1].value = "production"
      pipeline_runner._fetch_inputs(state)
      assert.eq(state.yaml_vars[1].value, "production")
    end)
  end)

  it("discards edits when the ref changes", function()
    with_mock(api, "pipeline_inputs", function()
      return {}, nil, { { key = "ENV", value = "staging", description = "Target" } }
    end, function()
      local state = { project = "ns/proj", ref = "main", fields = {}, yaml_vars = {}, yaml_vars_key = "" }
      pipeline_runner._fetch_inputs(state)
      state.yaml_vars[1].value = "production"
      state.ref = "feature"
      pipeline_runner._fetch_inputs(state)
      assert.eq(state.yaml_vars[1].value, "staging")
    end)
  end)

  it("preserves existing discovery state when yq returns an error", function()
    with_mock(api, "pipeline_inputs", function()
      return nil, "yq YAML-to-JSON multi-document capability is unavailable", nil
    end, function()
      local state = {
        project = "ns/proj", ref = "main",
        fields = { { name = "env", value = "prod" } },
        yaml_vars = { { key = "REGION", value = "eu" } }, yaml_vars_key = "ns/proj|main",
      }
      pipeline_runner._fetch_inputs(state)
      assert.eq(state.fields[1].value, "prod")
      assert.eq(state.yaml_vars[1].value, "eu")
    end)
  end)
end)

describe("merge_variables priority", function()
  it("manual variables override YAML variables", function()
    local result = pipeline_runner._merge_variables(
      { { key = "ENV", value = "yaml" } },
      { { key = "ENV", value = "manual" } }
    )
    assert.eq(#result, 1)
    assert.eq(result[1].value, "manual")
  end)
end)
