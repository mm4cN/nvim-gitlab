local M = {}

function M.run(cmd, opts)
  opts = opts or {}

  local result = vim.system(cmd, {
    text = true,
    cwd = opts.cwd,
    stdin = opts.stdin,
  }):wait()

  local stdout = vim.trim(result.stdout or "")
  local stderr = vim.trim(result.stderr or "")

  if result.code ~= 0 then
    return nil, stderr ~= "" and stderr or stdout
  end

  return stdout, nil
end

function M.run_json(cmd, opts)
  local output, err = M.run(cmd, opts)

  if err then
    return nil, err
  end

  if output == "" then
    return nil, "Empty JSON response"
  end

  local ok, decoded = pcall(vim.json.decode, output)

  if not ok then
    return nil, "Failed to decode JSON: " .. decoded
  end

  return decoded, nil
end

function M.run_async(cmd, opts, callback)
  opts = opts or {}
  vim.system(cmd, { text = true, cwd = opts.cwd }, function(result)
    local stdout = vim.trim(result.stdout or "")
    local stderr = vim.trim(result.stderr or "")
    if result.code ~= 0 then
      callback(nil, stderr ~= "" and stderr or stdout)
    else
      callback(stdout, nil)
    end
  end)
end

function M.run_json_async(cmd, opts, callback)
  M.run_async(cmd, opts, function(output, err)
    if err then
      callback(nil, err)
      return
    end
    if output == "" then
      callback(nil, "Empty JSON response")
      return
    end
    local ok, decoded = pcall(vim.json.decode, output)
    if not ok then
      callback(nil, "Failed to decode JSON: " .. decoded)
      return
    end
    callback(decoded, nil)
  end)
end

return M
