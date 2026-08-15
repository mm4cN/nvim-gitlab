local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local glab = require("gitlab.glab")
local api = require("gitlab.api")

-- parse_spec_inputs is a local function tested through api.pipeline_inputs.
-- glab.run is mocked to return fixture YAML; no network or file access occurs.

local function parse_yaml(content)
  local inputs, err
  with_mock(glab, "run", function()
    return content, nil
  end, function()
    inputs, err = api.pipeline_inputs({ ref = "main" })
  end)
  return inputs, err
end

describe("spec:inputs — no matching content", function()
  it("returns empty list when file has no spec: block", function()
    local inputs, err = parse_yaml("image: alpine\nstages:\n  - build\n")
    assert.is_nil(err)
    assert.eq(#inputs, 0)
  end)

  it("returns empty list when spec: has no inputs: key", function()
    local inputs, err = parse_yaml("spec:\n  other: value\n")
    assert.is_nil(err)
    assert.eq(#inputs, 0)
  end)

  it("returns empty list when inputs: block is empty", function()
    local inputs, err = parse_yaml("spec:\n  inputs:\n")
    assert.is_nil(err)
    assert.eq(#inputs, 0)
  end)

  it("returns nil and error when file content is empty", function()
    local inputs, err = parse_yaml("")
    assert.is_nil(inputs)
    assert.not_nil(err)
  end)
end)

describe("spec:inputs — simple inputs", function()
  it("parses a single input with no properties", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
]])
    assert.is_nil(err)
    assert.eq(#inputs, 1)
    assert.eq(inputs[1].name, "environment")
    assert.eq(inputs[1].type, "string")
    assert.eq(inputs[1].value, "")
  end)

  it("parses multiple inputs in order", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
    version:
    count:
]])
    assert.is_nil(err)
    assert.eq(#inputs, 3)
    assert.eq(inputs[1].name, "environment")
    assert.eq(inputs[2].name, "version")
    assert.eq(inputs[3].name, "count")
  end)

  it("skips comment lines without affecting state", function()
    local inputs, err = parse_yaml([[
# this is a comment
spec:
  inputs:
    # another comment
    environment:
]])
    assert.is_nil(err)
    assert.eq(#inputs, 1)
    assert.eq(inputs[1].name, "environment")
  end)

  it("skips blank lines without affecting state", function()
    local inputs, err = parse_yaml([[
spec:

  inputs:

    environment:

]])
    assert.is_nil(err)
    assert.eq(#inputs, 1)
    assert.eq(inputs[1].name, "environment")
  end)
end)

describe("spec:inputs — default values", function()
  it("sets value and default from unquoted default", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
      default: staging
]])
    assert.is_nil(err)
    assert.eq(inputs[1].default, "staging")
    assert.eq(inputs[1].value,   "staging")
  end)

  it("strips double quotes from default value", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
      default: "staging"
]])
    assert.is_nil(err)
    assert.eq(inputs[1].default, "staging")
    assert.eq(inputs[1].value,   "staging")
  end)

  it("strips single quotes from default value", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
      default: 'staging'
]])
    assert.is_nil(err)
    assert.eq(inputs[1].default, "staging")
    assert.eq(inputs[1].value,   "staging")
  end)

  it("sets value to empty string when no default is given", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
      description: some desc
]])
    assert.is_nil(err)
    assert.eq(inputs[1].value, "")
    assert.is_nil(inputs[1].default)
  end)
end)

describe("spec:inputs — descriptions", function()
  it("parses description", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
      description: Target deployment environment
]])
    assert.is_nil(err)
    assert.eq(inputs[1].description, "Target deployment environment")
  end)

  it("strips quotes from description", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
      description: "Target deployment environment"
]])
    assert.is_nil(err)
    assert.eq(inputs[1].description, "Target deployment environment")
  end)
end)

describe("spec:inputs — types", function()
  it("defaults to string type when type is absent", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
]])
    assert.is_nil(err)
    assert.eq(inputs[1].type, "string")
  end)

  it("parses number type", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    count:
      type: number
      default: 42
]])
    assert.is_nil(err)
    assert.eq(inputs[1].type,    "number")
    assert.eq(inputs[1].default, "42")
    assert.eq(inputs[1].value,   "42")
  end)

  it("parses boolean type", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    verbose:
      type: boolean
      default: false
]])
    assert.is_nil(err)
    assert.eq(inputs[1].type,    "boolean")
    assert.eq(inputs[1].default, "false")
  end)

  it("parses float default for number type", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    ratio:
      type: number
      default: 1.5
]])
    assert.is_nil(err)
    assert.eq(inputs[1].type,    "number")
    assert.eq(inputs[1].default, "1.5")
    assert.eq(inputs[1].value,   "1.5")
  end)
end)

describe("spec:inputs — block-style options", function()
  it("parses a block options list", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
      options:
        - dev
        - staging
        - prod
]])
    assert.is_nil(err)
    assert.not_nil(inputs[1].options)
    assert.eq(#inputs[1].options, 3)
    assert.eq(inputs[1].options[1], "dev")
    assert.eq(inputs[1].options[2], "staging")
    assert.eq(inputs[1].options[3], "prod")
  end)

  it("strips quotes from option values", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
      options:
        - "dev"
        - 'staging'
]])
    assert.is_nil(err)
    assert.eq(inputs[1].options[1], "dev")
    assert.eq(inputs[1].options[2], "staging")
  end)

  it("options and other properties coexist on the same input", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
      description: Target environment
      default: dev
      options:
        - dev
        - staging
]])
    assert.is_nil(err)
    assert.eq(inputs[1].description,    "Target environment")
    assert.eq(inputs[1].default,        "dev")
    assert.eq(#inputs[1].options,       2)
  end)
end)

describe("spec:inputs — content outside spec block", function()
  it("ignores top-level keys before spec:", function()
    local inputs, err = parse_yaml([[
image: alpine
stages:
  - build
spec:
  inputs:
    environment:
]])
    assert.is_nil(err)
    assert.eq(#inputs, 1)
    assert.eq(inputs[1].name, "environment")
  end)

  it("stops collecting inputs when a new top-level key follows spec:", function()
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
build-job:
  script:
    - echo hello
]])
    assert.is_nil(err)
    assert.eq(#inputs, 1)
    assert.eq(inputs[1].name, "environment")
  end)
end)

describe("spec:inputs — unsupported constructs fail safely", function()
  it("include: directive before spec: does not prevent input discovery", function()
    local inputs, err = parse_yaml([[
include:
  - local: /path/to/file.yml

spec:
  inputs:
    environment:
]])
    assert.is_nil(err)
    assert.eq(#inputs, 1)
    assert.eq(inputs[1].name, "environment")
  end)

  it("tab-indented input is not recognised and returns empty list safely", function()
    -- Tabs produce indent=1 which matches no parser branch; no error is raised.
    local inputs, err = parse_yaml("spec:\n  inputs:\n\tenvironment:\n")
    assert.is_nil(err)
    assert.eq(#inputs, 0)
  end)

  it("inline options form results in empty options list and does not error", function()
    -- options: [dev, staging] sets in_options=true and options={} but the inline
    -- value is not parsed; no indent-8 items follow, so options stays empty.
    local inputs, err = parse_yaml([[
spec:
  inputs:
    environment:
      options: [dev, staging]
]])
    assert.is_nil(err)
    assert.eq(#inputs, 1)
    assert.not_nil(inputs[1].options)
    assert.eq(#inputs[1].options, 0)
  end)

  it("block scalar description does not corrupt subsequent input parsing", function()
    -- description: | captures "|" as the description; subsequent indented lines
    -- are skipped; the next input at indent 4 is still parsed correctly.
    local inputs, err = parse_yaml([[
spec:
  inputs:
    first:
      description: |
        this is a long description
    second:
]])
    assert.is_nil(err)
    assert.eq(#inputs, 2)
    assert.eq(inputs[1].name, "first")
    assert.eq(inputs[2].name, "second")
  end)
end)
