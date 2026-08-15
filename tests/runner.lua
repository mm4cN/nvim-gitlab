local M = {}

local _passed = 0
local _failed = 0
local _current_suite = ""

function M.describe(name, fn)
  _current_suite = name
  fn()
  _current_suite = ""
end

function M.it(name, fn)
  local label = _current_suite ~= "" and (_current_suite .. " > " .. name) or name
  local ok, err = pcall(fn)
  if ok then
    _passed = _passed + 1
    print("  [PASS] " .. label)
  else
    _failed = _failed + 1
    print("  [FAIL] " .. label)
    print("         " .. tostring(err))
  end
end

M.assert = {}

-- assert.eq(actual, expected): actual is the value under test, expected is the reference value.
function M.assert.eq(actual, expected)
  if actual ~= expected then
    error(
      "expected " .. vim.inspect(expected) .. " got " .. vim.inspect(actual),
      2
    )
  end
end

function M.assert.is_nil(v)
  if v ~= nil then
    error("expected nil, got " .. vim.inspect(v), 2)
  end
end

function M.assert.not_nil(v)
  if v == nil then
    error("expected non-nil value", 2)
  end
end

function M.assert.truthy(v)
  if not v then
    error("expected truthy value, got " .. vim.inspect(v), 2)
  end
end

function M.assert.contains(str, pattern)
  if not str:find(pattern, 1, true) then
    error(vim.inspect(str) .. " does not contain " .. vim.inspect(pattern), 2)
  end
end

-- with_mock(tbl, key, replacement, fn) installs replacement on tbl[key],
-- runs fn, then always restores the original — even if fn throws.
function M.with_mock(tbl, key, replacement, fn)
  local orig = tbl[key]
  tbl[key] = replacement
  local ok, err = pcall(fn)
  tbl[key] = orig
  if not ok then
    error(err, 2)
  end
end

function M.report()
  local total = _passed + _failed
  print(string.format("\n%d/%d tests passed", _passed, total))
  if _failed > 0 then
    print(_failed .. " test(s) FAILED")
    os.exit(1)
  else
    os.exit(0)
  end
end

return M
