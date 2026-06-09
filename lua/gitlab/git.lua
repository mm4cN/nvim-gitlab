local process = require("gitlab.util.process")

local M = {}

function M.root()
  local output, err = process.run({
    "git",
    "rev-parse",
    "--show-toplevel",
  })

  if err then
    return nil, "Not inside a git repository"
  end

  return output, nil
end

function M.branch()
  local output, err = process.run({
    "git",
    "branch",
    "--show-current",
  })

  if err then
    return nil, "Cannot detect current branch"
  end

  if output == "" then
    return nil, "Detached HEAD is not supported yet"
  end

  return output, nil
end

function M.remote_url()
  local output, err = process.run({
    "git",
    "remote",
    "get-url",
    "origin",
  })

  if err then
    return nil, "Cannot detect origin remote"
  end

  return output, nil
end

return M
