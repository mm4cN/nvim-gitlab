local process = require("gitlab.util.process")

local M = {}

local SINGLE_PROBE_YAML = [[
mapping:
  nested: value
array: [one, two]
multiline: |
  first line
  second line
boolean: false
number: 3.5
]]

local MULTI_PROBE_YAML = [[
name: first
---
name: second
enabled: true
]]

local strategies = {
  { name = "compact-json", command = { "yq", "-c", ".", "-" } },
  { name = "json-indent-zero", command = { "yq", "-j", "-I=0", ".", "-" } },
}

local single_strategy = nil
local multi_strategy = nil
local single_checked = false
local multi_checked = false

local function decode_json_stream(output)
  local documents = {}
  for _, line in ipairs(vim.split(output, "\n", { plain = true, trimempty = true })) do
    local ok, decoded = pcall(vim.json.decode, line)
    if not ok then
      return nil, "invalid JSON document: " .. decoded
    end
    table.insert(documents, decoded)
  end
  if #documents == 0 then
    return nil, "empty JSON document stream"
  end
  return documents, nil
end

local function transcode(strategy, content, opts)
  local output, err = process.run(strategy.command, {
    cwd = opts and opts.cwd,
    stdin = content,
  })
  if not output then
    return nil, err
  end
  return decode_json_stream(output)
end

local function valid_single(documents)
  local document = documents and documents[1]
  return #documents == 1
    and type(document) == "table"
    and type(document.mapping) == "table"
    and document.mapping.nested == "value"
    and type(document.array) == "table"
    and document.array[1] == "one"
    and document.array[2] == "two"
    and document.multiline == "first line\nsecond line\n"
    and document.boolean == false
    and document.number == 3.5
end

local function valid_multi(documents)
  return documents
    and #documents == 2
    and documents[1].name == "first"
    and documents[2].name == "second"
    and documents[2].enabled == true
end

local function find_strategy(content, validator)
  local last_err = nil
  for _, strategy in ipairs(strategies) do
    local documents, err = transcode(strategy, content)
    if documents and validator(documents) then
      return strategy, nil
    end
    last_err = err or "unexpected decoded document structure"
  end
  return nil, last_err
end

local function ensure_single()
  if not single_checked then
    single_strategy = select(1, find_strategy(SINGLE_PROBE_YAML, valid_single))
    single_checked = true
  end
  if not single_strategy then
    return nil, "yq YAML-to-JSON single-document capability is unavailable"
  end
  return single_strategy, nil
end

local function ensure_multi()
  if not multi_checked then
    multi_strategy = select(1, find_strategy(MULTI_PROBE_YAML, valid_multi))
    multi_checked = true
  end
  if not multi_strategy then
    return nil, "yq YAML-to-JSON multi-document capability is unavailable"
  end
  return multi_strategy, nil
end

function M.check(opts)
  opts = opts or {}
  if opts.force then
    M._reset_probe_cache()
  end

  local _, single_err = ensure_single()
  if single_err then
    return nil, single_err
  end
  local _, multi_err = ensure_multi()
  if multi_err then
    return nil, multi_err
  end
  return true, nil
end

function M.parse_documents(content, opts)
  opts = opts or {}
  local strategy, err
  if opts.multiple then
    strategy, err = ensure_multi()
  else
    strategy, err = ensure_single()
  end
  if not strategy then
    return nil, err
  end
  return transcode(strategy, content, opts)
end

function M._reset_probe_cache()
  single_strategy = nil
  multi_strategy = nil
  single_checked = false
  multi_checked = false
end

return M
