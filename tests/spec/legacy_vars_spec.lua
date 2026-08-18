local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local glab = require("gitlab.glab")
local api = require("gitlab.api")
local pipeline_runner = require("gitlab.ci.pipeline_runner")

-- parse_legacy_variables is a local function; tested through api.pipeline_inputs
-- (third return value) with glab.run_json mocked to return merged_yaml fixtures.

-- pipeline_inputs calls glab.run for the raw CI file and glab.run_json for ci/lint.
-- Both are mocked: run returns the content directly; run_json returns it as merged_yaml.
local function parse_yaml_vars(content)
  local yaml_vars, err
  with_mock(glab, "run", function()
    return content, nil
  end, function()
    with_mock(glab, "run_json", function()
      return { merged_yaml = content }, nil
    end, function()
      local _, e, yv = api.pipeline_inputs({ project = "ns/proj", ref = "main" })
      yaml_vars = yv
      err = e
    end)
  end)
  return yaml_vars, err
end

-- ──────────────────────────────────────────────────────────────────────────────
-- parse_legacy_variables — discovery
-- ──────────────────────────────────────────────────────────────────────────────

describe("parse_legacy_variables — basic discovery", function()
  it("returns empty list when there is no variables: block", function()
    local vars = parse_yaml_vars("image: alpine\nstages:\n  - build\n")
    assert.eq(#vars, 0)
  end)

  it("returns empty list when variables: block is absent", function()
    local vars = parse_yaml_vars("spec:\n  inputs:\n    env:\n")
    assert.eq(#vars, 0)
  end)

  it("discovers a variable with both value and description", function()
    local vars = parse_yaml_vars([[
variables:
  ENVIRONMENT:
    value: staging
    description: Target environment
]])
    assert.eq(#vars, 1)
    assert.eq(vars[1].key, "ENVIRONMENT")
    assert.eq(vars[1].value, "staging")
    assert.eq(vars[1].description, "Target environment")
  end)

  it("discovers multiple described variables in order", function()
    local vars = parse_yaml_vars([[
variables:
  ENV:
    value: staging
    description: Target environment
  REGION:
    value: eu-west-1
    description: AWS region
]])
    assert.eq(#vars, 2)
    assert.eq(vars[1].key, "ENV")
    assert.eq(vars[2].key, "REGION")
  end)

  it("strips double quotes from value and description", function()
    local vars = parse_yaml_vars([[
variables:
  ENV:
    value: "staging"
    description: "Target environment"
]])
    assert.eq(vars[1].value, "staging")
    assert.eq(vars[1].description, "Target environment")
  end)

  it("strips single quotes from value and description", function()
    local vars = parse_yaml_vars([[
variables:
  ENV:
    value: 'staging'
    description: 'Target environment'
]])
    assert.eq(vars[1].value, "staging")
    assert.eq(vars[1].description, "Target environment")
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- parse_legacy_variables — exclusion rules
-- ──────────────────────────────────────────────────────────────────────────────

describe("parse_legacy_variables — exclusion rules", function()
  it("excludes inline assignment (no description possible)", function()
    local vars = parse_yaml_vars([[
variables:
  SECRET: top-secret
]])
    assert.eq(#vars, 0)
  end)

  it("excludes a block variable with no description field", function()
    local vars = parse_yaml_vars([[
variables:
  TOKEN:
    value: abc123
]])
    assert.eq(#vars, 0)
  end)

  it("excludes a block variable with an empty description", function()
    local vars = parse_yaml_vars([[
variables:
  TOKEN:
    value: abc123
    description: ""
]])
    assert.eq(#vars, 0)
  end)

  it("excludes a block variable with no value field", function()
    local vars = parse_yaml_vars([[
variables:
  LABEL:
    description: Only a description
]])
    assert.eq(#vars, 0)
  end)

  it("mixes described and non-described variables correctly", function()
    local vars = parse_yaml_vars([[
variables:
  INLINE: value
  HIDDEN:
    value: secret
  VISIBLE:
    value: staging
    description: Target environment
]])
    assert.eq(#vars, 1)
    assert.eq(vars[1].key, "VISIBLE")
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- parse_legacy_variables — coexistence with spec:inputs
-- ──────────────────────────────────────────────────────────────────────────────

describe("parse_legacy_variables — coexistence with spec:inputs", function()
  it("returns both spec:inputs and yaml_vars from the same content", function()
    local content = [[
spec:
  inputs:
    deploy_env:
      description: Deployment target
variables:
  REGION:
    value: eu-west-1
    description: AWS region
]]
    local inputs, err, yaml_vars
    with_mock(glab, "run", function()
      return content, nil
    end, function()
      with_mock(glab, "run_json", function()
        return { merged_yaml = content }, nil
      end, function()
        inputs, err, yaml_vars = api.pipeline_inputs({ project = "ns/proj", ref = "main" })
      end)
    end)
    assert.is_nil(err)
    assert.eq(#inputs, 1)
    assert.eq(inputs[1].name, "deploy_env")
    assert.eq(#yaml_vars, 1)
    assert.eq(yaml_vars[1].key, "REGION")
  end)

  it("stops collecting variables when a non-variables top-level key follows", function()
    local vars = parse_yaml_vars([[
variables:
  ENV:
    value: staging
    description: Target environment
image: alpine
]])
    assert.eq(#vars, 1)
    assert.eq(vars[1].key, "ENV")
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- fetch_inputs — yaml_vars state management
-- ──────────────────────────────────────────────────────────────────────────────

local fetch_inputs = pipeline_runner.fetch_inputs

describe("fetch_inputs — yaml_vars scoping", function()
  it("populates state.yaml_vars from pipeline_inputs third return value", function()
    with_mock(api, "pipeline_inputs", function()
      return {}, nil, { { key = "ENV", value = "staging", description = "Target env" } }
    end, function()
      local state = {
        project = "ns/proj", ref = "main", root = nil,
        fields = {}, yaml_vars = {}, yaml_vars_key = "",
      }
      fetch_inputs(state)
      assert.eq(#state.yaml_vars, 1)
      assert.eq(state.yaml_vars[1].key, "ENV")
      assert.eq(state.yaml_vars[1].value, "staging")
    end)
  end)

  it("preserves user-edited yaml_var value across a refresh on the same project+ref", function()
    with_mock(api, "pipeline_inputs", function()
      return {}, nil, { { key = "ENV", value = "staging", description = "Target env" } }
    end, function()
      local state = {
        project = "ns/proj", ref = "main", root = nil,
        fields = {}, yaml_vars = {}, yaml_vars_key = "",
      }
      fetch_inputs(state)
      assert.eq(state.yaml_vars[1].value, "staging")

      -- User edits the value
      state.yaml_vars[1].value = "production"

      -- Refresh same project+ref: edited value must survive
      fetch_inputs(state)
      assert.eq(state.yaml_vars[1].value, "production")
    end)
  end)

  it("discards yaml_var edits when ref changes", function()
    local call = 0
    with_mock(api, "pipeline_inputs", function()
      call = call + 1
      return {}, nil, { { key = "ENV", value = "staging", description = "Target env" } }
    end, function()
      local state = {
        project = "ns/proj", ref = "main", root = nil,
        fields = {}, yaml_vars = {}, yaml_vars_key = "",
      }

      fetch_inputs(state)
      state.yaml_vars[1].value = "production"

      -- Switch ref
      state.ref = "develop"
      fetch_inputs(state)

      -- Fresh value from the new fetch must not be overridden by the stale edit
      assert.eq(state.yaml_vars[1].value, "staging")
    end)
    assert.eq(call, 2)
  end)

  it("discards yaml_var edits when project changes", function()
    with_mock(api, "pipeline_inputs", function()
      return {}, nil, { { key = "ENV", value = "staging", description = "Target env" } }
    end, function()
      local state = {
        project = "ns/proj", ref = "main", root = nil,
        fields = {}, yaml_vars = {}, yaml_vars_key = "",
      }

      fetch_inputs(state)
      state.yaml_vars[1].value = "production"

      -- Switch project
      state.project = "ns/other"
      fetch_inputs(state)

      assert.eq(state.yaml_vars[1].value, "staging")
    end)
  end)

  it("clears yaml_vars when pipeline_inputs returns no yaml_vars", function()
    with_mock(api, "pipeline_inputs", function()
      return {}, nil, nil
    end, function()
      local state = {
        project = "ns/proj", ref = "main", root = nil,
        fields = {},
        yaml_vars = { { key = "STALE", value = "x", description = "d" } },
        yaml_vars_key = "ns/proj|other",
      }
      fetch_inputs(state)
      assert.eq(#state.yaml_vars, 0)
    end)
  end)

  it("does not call pipeline_inputs when project is empty", function()
    local called = false
    with_mock(api, "pipeline_inputs", function()
      called = true
      return {}, nil, {}
    end, function()
      local state = {
        project = "", ref = "main", root = nil,
        fields = {}, yaml_vars = {}, yaml_vars_key = "",
      }
      fetch_inputs(state)
    end)
    assert.eq(called, false)
  end)

  it("does not call pipeline_inputs when ref is empty", function()
    local called = false
    with_mock(api, "pipeline_inputs", function()
      called = true
      return {}, nil, {}
    end, function()
      local state = {
        project = "ns/proj", ref = "", root = nil,
        fields = {}, yaml_vars = {}, yaml_vars_key = "",
      }
      fetch_inputs(state)
    end)
    assert.eq(called, false)
  end)

  it("preserves existing fields and yaml_vars when pipeline_inputs returns an error (regression)", function()
    with_mock(api, "pipeline_inputs", function()
      return nil, "ci/lint request failed", nil
    end, function()
      local state = {
        project = "ns/proj", ref = "main", root = nil,
        fields = { { name = "deploy_env", value = "staging", type = "string" } },
        yaml_vars = { { key = "REGION", value = "eu-west-1", description = "AWS region" } },
        yaml_vars_key = "ns/proj|main",
      }
      fetch_inputs(state)
      assert.eq(#state.fields, 1)
      assert.eq(state.fields[1].name, "deploy_env")
      assert.eq(#state.yaml_vars, 1)
      assert.eq(state.yaml_vars[1].key, "REGION")
    end)
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- merge_variables — three-tier priority (API < YAML < manual)
-- ──────────────────────────────────────────────────────────────────────────────

-- ──────────────────────────────────────────────────────────────────────────────
-- fetch_inputs — ref switching (regression)
-- ──────────────────────────────────────────────────────────────────────────────

describe("fetch_inputs — ref switching populates spec:inputs immediately", function()
  it("updates state.fields when switching from a ref without inputs to one with spec:inputs", function()
    with_mock(api, "pipeline_inputs", function(opts)
      if opts.ref == "feature" then
        return {
          { name = "deploy_env", type = "string", default = nil, options = nil, description = "" },
        }, nil, {}
      end
      return {}, nil, {}
    end, function()
      local state = {
        project = "ns/proj", ref = "main", root = nil,
        fields = {}, yaml_vars = {}, yaml_vars_key = "",
      }

      fetch_inputs(state)
      assert.eq(#state.fields, 0)

      state.ref = "feature"
      fetch_inputs(state)
      assert.eq(#state.fields, 1)
      assert.eq(state.fields[1].name, "deploy_env")
    end)
  end)
end)

local merge = pipeline_runner.merge_variables

describe("merge_variables — three-tier priority", function()
  it("yaml_var overrides api_var for the same key", function()
    local api_vars  = { { key = "ENV", value = "api" } }
    local yaml_vars = { { key = "ENV", value = "yaml" } }
    local result = merge(merge(api_vars, yaml_vars), {})
    assert.eq(#result, 1)
    assert.eq(result[1].value, "yaml")
  end)

  it("manual_var overrides yaml_var for the same key", function()
    local yaml_vars   = { { key = "ENV", value = "yaml" } }
    local manual_vars = { { key = "ENV", value = "manual" } }
    local result = merge(yaml_vars, manual_vars)
    assert.eq(#result, 1)
    assert.eq(result[1].value, "manual")
  end)

  it("manual_var overrides api_var through the full three-tier chain", function()
    local api_vars    = { { key = "ENV", value = "api" } }
    local yaml_vars   = { { key = "ENV", value = "yaml" } }
    local manual_vars = { { key = "ENV", value = "manual" } }
    local result = merge(merge(api_vars, yaml_vars), manual_vars)
    assert.eq(#result, 1)
    assert.eq(result[1].value, "manual")
  end)

  it("keys unique to each tier are all present in the output", function()
    local api_vars    = { { key = "A", value = "api-a" } }
    local yaml_vars   = { { key = "B", value = "yaml-b" } }
    local manual_vars = { { key = "C", value = "manual-c" } }
    local result = merge(merge(api_vars, yaml_vars), manual_vars)
    assert.eq(#result, 3)
    local by_key = {}
    for _, v in ipairs(result) do by_key[v.key] = v.value end
    assert.eq(by_key["A"], "api-a")
    assert.eq(by_key["B"], "yaml-b")
    assert.eq(by_key["C"], "manual-c")
  end)
end)
