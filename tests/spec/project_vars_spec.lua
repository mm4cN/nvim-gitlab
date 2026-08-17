local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local api = require("gitlab.api")
local pipeline_runner = require("gitlab.ci.pipeline_runner")

local normalize = pipeline_runner.normalize_project_vars
local fetch    = pipeline_runner.fetch_project_vars
local merge    = pipeline_runner.merge_variables

-- ──────────────────────────────────────────────────────────────────────────────
-- normalize_project_vars — filtering and metadata preservation
-- ──────────────────────────────────────────────────────────────────────────────

describe("normalize_project_vars — filtering", function()
  it("exposes a variable with a non-empty description", function()
    local result = normalize({
      { key = "DEPLOY_USER", value = "alice", description = "Deployment user" },
    }, {})
    assert.eq(#result, 1)
    assert.eq(result[1].key, "DEPLOY_USER")
  end)

  it("ignores a variable without a description field", function()
    local result = normalize({
      { key = "SECRET", value = "x" },
    }, {})
    assert.eq(#result, 0)
  end)

  it("ignores a variable with an empty description", function()
    local result = normalize({
      { key = "TOKEN", value = "abc", description = "" },
    }, {})
    assert.eq(#result, 0)
  end)

  it("preserves full variable metadata (not just key/value/description)", function()
    local result = normalize({
      {
        key = "REGION", value = "eu-west-1", description = "Target region",
        variable_type = "env_var", protected = true, masked = false,
        hidden = false, environment_scope = "*",
      },
    }, {})
    assert.eq(#result, 1)
    assert.eq(result[1].protected, true)
    assert.eq(result[1].variable_type, "env_var")
    assert.eq(result[1].environment_scope, "*")
  end)

  it("works when raw_vars is empty", function()
    local result = normalize({}, {})
    assert.eq(#result, 0)
  end)

  it("works when raw_vars is nil", function()
    local result = normalize(nil, {})
    assert.eq(#result, 0)
  end)
end)

describe("normalize_project_vars — edited-value preservation", function()
  it("preserves a user-edited value over the freshly fetched API value (regression)", function()
    -- API returns "staging"; user previously edited to "production"
    local raw = { { key = "ENV", value = "staging", description = "Target environment" } }
    local existing = { ENV = "production" }
    local result = normalize(raw, existing)
    assert.eq(result[1].value, "production")
  end)

  it("uses the API value when no edited value exists", function()
    local raw = { { key = "ENV", value = "staging", description = "Target environment" } }
    local result = normalize(raw, {})
    assert.eq(result[1].value, "staging")
  end)

  it("uses empty string when API value is nil and no edited value exists", function()
    local raw = { { key = "ENV", description = "Target environment" } }
    local result = normalize(raw, {})
    assert.eq(result[1].value, "")
  end)

  it("does not confuse edited values across different keys", function()
    local raw = {
      { key = "A", value = "api-a", description = "Var A" },
      { key = "B", value = "api-b", description = "Var B" },
    }
    local existing = { A = "edited-a" }
    local result = normalize(raw, existing)
    assert.eq(result[1].value, "edited-a")
    assert.eq(result[2].value, "api-b")
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- fetch_project_vars — ref independence
-- ──────────────────────────────────────────────────────────────────────────────

describe("fetch_project_vars — ref independence", function()
  it("fetches and populates state.project_vars when ref is empty", function()
    with_mock(api, "variables", function(opts)
      -- ref must not have been passed by fetch_project_vars
      assert.is_nil(opts.ref)
      return {
        { key = "REGION", value = "eu-west-1", description = "Target region" },
      }, nil
    end, function()
      local state = { project = "ns/proj", ref = "", root = nil, project_vars = {} }
      fetch(state)
      assert.eq(#state.project_vars, 1)
      assert.eq(state.project_vars[1].key, "REGION")
    end)
  end)

  it("does not call api.variables when project is empty", function()
    local called = false
    with_mock(api, "variables", function()
      called = true
      return {}, nil
    end, function()
      local state = { project = "", ref = "main", root = nil, project_vars = {} }
      fetch(state)
    end)
    assert.eq(called, false)
  end)

  it("preserves edited values across a fetch/refresh cycle for the same project (regression)", function()
    with_mock(api, "variables", function()
      return { { key = "ENV", value = "staging", description = "Target env" } }, nil
    end, function()
      local state = {
        project = "ns/proj", ref = "", root = nil,
        project_vars = {}, project_vars_project = "",
      }
      fetch(state)
      assert.eq(state.project_vars[1].value, "staging")

      -- User edits the value
      state.project_vars[1].value = "production"

      -- Refresh same project: edited value must survive
      fetch(state)
      assert.eq(state.project_vars[1].value, "production")
    end)
  end)

  it("discards previous project edits when project changes (regression)", function()
    local project_a_called = false
    local project_b_called = false

    with_mock(api, "variables", function(opts)
      if opts.project == "ns/proj-a" then
        project_a_called = true
        return { { key = "ENV", value = "staging", description = "Target env" } }, nil
      else
        project_b_called = true
        return { { key = "ENV", value = "development", description = "Target env" } }, nil
      end
    end, function()
      local state = {
        project = "ns/proj-a", ref = "", root = nil,
        project_vars = {}, project_vars_project = "",
      }

      -- Fetch Project A; user edits ENV to "production"
      fetch(state)
      assert.eq(state.project_vars[1].value, "staging")
      state.project_vars[1].value = "production"

      -- Switch to Project B
      state.project = "ns/proj-b"
      fetch(state)

      -- Project B's API value "development" must not be overridden by Project A's edit
      assert.eq(state.project_vars[1].value, "development")
    end)

    assert.truthy(project_a_called)
    assert.truthy(project_b_called)
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- spec:inputs and project vars coexist
-- ──────────────────────────────────────────────────────────────────────────────

describe("spec:inputs and project variables coexistence", function()
  it("normalizing project vars does not affect a spec:inputs list", function()
    local spec_inputs = { { name = "env", type = "string", value = "staging" } }
    local raw_vars = {
      { key = "REGION", value = "eu-west-1", description = "Target region" },
      { key = "HIDDEN", value = "s3cr3t" },
    }
    local proj_vars = normalize(raw_vars, {})
    -- Each list is independent
    assert.eq(#spec_inputs, 1)
    assert.eq(#proj_vars, 1)
    assert.eq(proj_vars[1].key, "REGION")
    assert.eq(spec_inputs[1].name, "env")
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- merge_variables — basic coexistence
-- ──────────────────────────────────────────────────────────────────────────────

describe("merge_variables — basic coexistence", function()
  it("includes project vars in the result", function()
    local result = merge({ { key = "A", value = "1" } }, {})
    assert.eq(#result, 1)
    assert.eq(result[1].key, "A")
    assert.eq(result[1].value, "1")
  end)

  it("includes manual vars in the result", function()
    local result = merge({}, { { key = "B", value = "2" } })
    assert.eq(#result, 1)
    assert.eq(result[1].key, "B")
  end)

  it("includes both when keys are distinct", function()
    local result = merge(
      { { key = "A", value = "proj" } },
      { { key = "B", value = "manual" } }
    )
    assert.eq(#result, 2)
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- merge_variables — manual override semantics
-- ──────────────────────────────────────────────────────────────────────────────

describe("merge_variables — manual override semantics", function()
  it("manual variable overrides project variable with the same key", function()
    local result = merge(
      { { key = "ENV", value = "staging" } },
      { { key = "ENV", value = "production" } }
    )
    assert.eq(#result, 1)
    assert.eq(result[1].key, "ENV")
    assert.eq(result[1].value, "production")
  end)

  it("final payload contains no duplicate keys", function()
    local result = merge(
      { { key = "X", value = "proj" }, { key = "Y", value = "proj-y" } },
      { { key = "X", value = "manual" } }
    )
    local keys = {}
    for _, v in ipairs(result) do
      assert.is_nil(keys[v.key], "duplicate key found: " .. v.key)
      keys[v.key] = true
    end
    assert.eq(#result, 2)
  end)

  it("override preserves the correct value from manual variable", function()
    local result = merge(
      { { key = "TOKEN", value = "old-token" } },
      { { key = "TOKEN", value = "new-token" } }
    )
    assert.eq(result[1].value, "new-token")
  end)

  it("edited project-variable value reaches the trigger payload", function()
    -- Simulate: API value "staging", user edited to "production",
    -- normalize preserves the edit, merge passes it through unchanged.
    local raw = { { key = "ENV", value = "staging", description = "Target env" } }
    local normed = normalize(raw, { ENV = "production" })
    assert.eq(normed[1].value, "production")
    local payload = merge(normed, {})
    assert.eq(payload[1].value, "production")
  end)

  it("multiple manual vars can override distinct project vars", function()
    local result = merge(
      { { key = "A", value = "pa" }, { key = "B", value = "pb" } },
      { { key = "A", value = "ma" }, { key = "B", value = "mb" } }
    )
    assert.eq(#result, 2)
    local by_key = {}
    for _, v in ipairs(result) do by_key[v.key] = v.value end
    assert.eq(by_key["A"], "ma")
    assert.eq(by_key["B"], "mb")
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- merge_variables — edge cases
-- ──────────────────────────────────────────────────────────────────────────────

describe("merge_variables — edge cases", function()
  it("skips project vars with empty keys", function()
    local result = merge({ { key = "", value = "ignored" } }, {})
    assert.eq(#result, 0)
  end)

  it("skips manual vars with empty keys", function()
    local result = merge({}, { { key = "", value = "ignored" } })
    assert.eq(#result, 0)
  end)

  it("returns empty list when both inputs are empty", function()
    local result = merge({}, {})
    assert.eq(#result, 0)
  end)
end)
