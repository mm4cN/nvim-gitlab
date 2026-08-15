local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local process = require("gitlab.util.process")
local glab = require("gitlab.glab")

-- run_pipeline builds its args array, prepends the glab binary via cmd(),
-- then calls process.run. Mocking process.run captures the full command.

local function capture_args(fn)
  local captured
  with_mock(process, "run", function(args)
    captured = args
    return "", nil
  end, fn)
  return captured
end

-- Returns all values that immediately follow `flag` in args.
local function all_after(args, flag)
  local values = {}
  for i, v in ipairs(args) do
    if v == flag and args[i + 1] then
      table.insert(values, args[i + 1])
    end
  end
  return values
end

-- Returns the first value immediately following `flag`, or nil.
local function first_after(args, flag)
  return all_after(args, flag)[1]
end

-- Returns true if `value` appears anywhere in args.
local function has_arg(args, value)
  for _, v in ipairs(args) do
    if v == value then return true end
  end
  return false
end

describe("glab.run_pipeline — ref validation", function()
  it("returns error when ref is absent", function()
    local result, err = glab.run_pipeline({})
    assert.is_nil(result)
    assert.eq(err, "ref is required")
  end)

  it("returns error when ref is empty string", function()
    local result, err = glab.run_pipeline({ ref = "" })
    assert.is_nil(result)
    assert.eq(err, "ref is required")
  end)
end)

describe("glab.run_pipeline — base args", function()
  it("emits ci run -b <ref>", function()
    local args = capture_args(function()
      glab.run_pipeline({ ref = "main" })
    end)
    assert.eq(first_after(args, "-b"), "main")
    assert.truthy(has_arg(args, "ci"))
    assert.truthy(has_arg(args, "run"))
  end)

  it("emits --repo when project is provided", function()
    local args = capture_args(function()
      glab.run_pipeline({ ref = "main", project = "ns/proj" })
    end)
    assert.eq(first_after(args, "--repo"), "ns/proj")
  end)

  it("omits --repo when project is absent", function()
    local args = capture_args(function()
      glab.run_pipeline({ ref = "main" })
    end)
    assert.eq(has_arg(args, "--repo"), false)
  end)

  it("omits --repo when project is empty string", function()
    local args = capture_args(function()
      glab.run_pipeline({ ref = "main", project = "" })
    end)
    assert.eq(has_arg(args, "--repo"), false)
  end)
end)

describe("glab.run_pipeline — typed inputs", function()
  local function run_with_input(input)
    return capture_args(function()
      glab.run_pipeline({ ref = "main", inputs = { input } })
    end)
  end

  it("encodes string input as key:value", function()
    local args = run_with_input({ name = "env", value = "staging", type = "string" })
    assert.eq(first_after(args, "--input"), "env:staging")
  end)

  it("encodes string input when type is omitted", function()
    local args = run_with_input({ name = "env", value = "staging" })
    assert.eq(first_after(args, "--input"), "env:staging")
  end)

  it("encodes integer number input as key:int(n)", function()
    local args = run_with_input({ name = "count", value = "42", type = "number" })
    assert.eq(first_after(args, "--input"), "count:int(42)")
  end)

  it("encodes negative integer as key:int(n)", function()
    local args = run_with_input({ name = "offset", value = "-5", type = "number" })
    assert.eq(first_after(args, "--input"), "offset:int(-5)")
  end)

  it("encodes float number input as key:float(n)", function()
    local args = run_with_input({ name = "ratio", value = "1.5", type = "number" })
    assert.eq(first_after(args, "--input"), "ratio:float(1.5)")
  end)

  it("encodes boolean true as key:bool(true)", function()
    local args = run_with_input({ name = "flag", value = "true", type = "boolean" })
    assert.eq(first_after(args, "--input"), "flag:bool(true)")
  end)

  it("encodes boolean false as key:bool(false)", function()
    local args = run_with_input({ name = "flag", value = "false", type = "boolean" })
    assert.eq(first_after(args, "--input"), "flag:bool(false)")
  end)

  it("encodes array input as key:array(values)", function()
    local args = run_with_input({ name = "tags", value = "a,b,c", type = "array" })
    assert.eq(first_after(args, "--input"), "tags:array(a,b,c)")
  end)

  it("emits multiple --input flags for multiple inputs", function()
    local args = capture_args(function()
      glab.run_pipeline({
        ref = "main",
        inputs = {
          { name = "env",   value = "staging", type = "string" },
          { name = "count", value = "3",       type = "number" },
        },
      })
    end)
    local inputs = all_after(args, "--input")
    assert.eq(#inputs, 2)
    assert.eq(inputs[1], "env:staging")
    assert.eq(inputs[2], "count:int(3)")
  end)
end)

describe("glab.run_pipeline — input validation errors", function()
  local function run_bad_input(input)
    return glab.run_pipeline({ ref = "main", inputs = { input } })
  end

  it("returns error when input name is missing", function()
    local result, err = run_bad_input({ name = "", value = "x", type = "string" })
    assert.is_nil(result)
    assert.eq(err, "pipeline input is missing a name")
  end)

  it("returns error when input name is nil", function()
    local result, err = run_bad_input({ value = "x", type = "string" })
    assert.is_nil(result)
    assert.eq(err, "pipeline input is missing a name")
  end)

  it("returns error for invalid number value", function()
    local result, err = run_bad_input({ name = "n", value = "abc", type = "number" })
    assert.is_nil(result)
    assert.contains(err, "invalid number value for 'n'")
  end)

  it("returns error for invalid boolean value", function()
    local result, err = run_bad_input({ name = "flag", value = "yes", type = "boolean" })
    assert.is_nil(result)
    assert.contains(err, "invalid boolean value for 'flag'")
  end)

  it("returns error for empty array value", function()
    local result, err = run_bad_input({ name = "tags", value = "", type = "array" })
    assert.is_nil(result)
    assert.contains(err, "empty array value for 'tags'")
  end)

  it("returns error for YAML sequence array value", function()
    local result, err = run_bad_input({ name = "tags", value = "- a", type = "array" })
    assert.is_nil(result)
    assert.contains(err, "unsupported array value for 'tags'")
  end)

  it("returns error for JSON array value", function()
    local result, err = run_bad_input({ name = "tags", value = "[a,b]", type = "array" })
    assert.is_nil(result)
    assert.contains(err, "unsupported array value for 'tags'")
  end)

  it("does not call process.run when an input is invalid", function()
    local called = false
    with_mock(process, "run", function()
      called = true
      return "", nil
    end, function()
      glab.run_pipeline({
        ref = "main",
        inputs = { { name = "n", value = "bad", type = "number" } },
      })
    end)
    assert.eq(called, false)
  end)
end)

describe("glab.run_pipeline — pipeline variables", function()
  it("emits --variable KEY=VALUE for a variable", function()
    local args = capture_args(function()
      glab.run_pipeline({
        ref = "main",
        variables = { { key = "VERSION", value = "1.2.3" } },
      })
    end)
    assert.eq(first_after(args, "--variable"), "VERSION=1.2.3")
  end)

  it("emits multiple --variable flags for multiple variables", function()
    local args = capture_args(function()
      glab.run_pipeline({
        ref = "main",
        variables = {
          { key = "VERSION", value = "1.2.3" },
          { key = "ENV",     value = "staging" },
        },
      })
    end)
    local vars = all_after(args, "--variable")
    assert.eq(#vars, 2)
    assert.eq(vars[1], "VERSION=1.2.3")
    assert.eq(vars[2], "ENV=staging")
  end)

  it("skips variables with empty key", function()
    local args = capture_args(function()
      glab.run_pipeline({
        ref = "main",
        variables = { { key = "", value = "x" } },
      })
    end)
    assert.eq(has_arg(args, "--variable"), false)
  end)

  it("uses empty string when variable value is nil", function()
    local args = capture_args(function()
      glab.run_pipeline({
        ref = "main",
        variables = { { key = "FOO", value = nil } },
      })
    end)
    assert.eq(first_after(args, "--variable"), "FOO=")
  end)
end)

describe("glab.run_pipeline — inputs and variables are independent", function()
  it("inputs use --input and variables use --variable, never mixed", function()
    local args = capture_args(function()
      glab.run_pipeline({
        ref = "main",
        inputs    = { { name = "env",     value = "prod",  type = "string" } },
        variables = { { key  = "VERSION", value = "2.0.0" } },
      })
    end)
    assert.eq(first_after(args, "--input"),    "env:prod")
    assert.eq(first_after(args, "--variable"), "VERSION=2.0.0")
  end)

  it("no --variable flag is emitted when variables list is absent", function()
    local args = capture_args(function()
      glab.run_pipeline({ ref = "main", inputs = { { name = "x", value = "y" } } })
    end)
    assert.eq(has_arg(args, "--variable"), false)
  end)

  it("no --input flag is emitted when inputs list is absent", function()
    local args = capture_args(function()
      glab.run_pipeline({ ref = "main", variables = { { key = "K", value = "V" } } })
    end)
    assert.eq(has_arg(args, "--input"), false)
  end)
end)
