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

function M.remote_project()
  local remote, err = M.remote_url()

  if not remote then
    return nil, err
  end

  local project = remote:match("^git@[^:]+:(.+)$")
      or remote:match("^https?://[^/]+/(.+)$")
      or remote:match("^ssh://git@[^/]+[:/](.+)$")

  if not project or project == "" then
    return nil, "Cannot extract project path from remote: " .. remote
  end

  project = project:gsub("%.git$", "")

  return project, nil
end

function M.remote_host()
  local remote, err = M.remote_url()

  if not remote then
    return nil, err
  end

  local host = remote:match("^git@([^:]+):")
      or remote:match("^https?://([^/]+)")
      or remote:match("^ssh://git@([^/]+)")

  if not host or host == "" then
    return nil, "Cannot extract GitLab host from remote: " .. remote
  end

  return host, nil
end

function M.root_async(callback)
  process.run_async({ "git", "rev-parse", "--show-toplevel" }, {}, function(output, err)
    if err then
      callback(nil, "Not inside a git repository")
    else
      callback(output, nil)
    end
  end)
end

function M.remote_url_async(callback)
  process.run_async({ "git", "remote", "get-url", "origin" }, {}, function(output, err)
    if err then
      callback(nil, "Cannot detect origin remote")
    else
      callback(output, nil)
    end
  end)
end

function M.remote_project_async(callback)
  M.remote_url_async(function(remote, err)
    if err then
      callback(nil, err)
      return
    end
    local project = remote:match("^git@[^:]+:(.+)$")
        or remote:match("^https?://[^/]+/(.+)$")
        or remote:match("^ssh://git@[^/]+[:/](.+)$")
    if not project or project == "" then
      callback(nil, "Cannot extract project path from remote: " .. remote)
      return
    end
    callback(project:gsub("%.git$", ""), nil)
  end)
end

function M.branch_async(callback)
  process.run_async({ "git", "branch", "--show-current" }, {}, function(output, err)
    if err then
      callback(nil, "Cannot detect current branch")
    elseif output == "" then
      callback(nil, "Detached HEAD is not supported yet")
    else
      callback(output, nil)
    end
  end)
end

return M
