local git = require("gitlab.git")

local M = {}

-- Returns a complete project context for cwd or nil, err.
function M.from_cwd()
  local root, root_err = git.root()
  if not root then
    return nil, root_err or "cannot resolve git repository root"
  end

  local project, project_err = git.remote_project()
  if not project then
    return nil, project_err or "cannot resolve GitLab project from remote"
  end

  local ref, ref_err = git.branch()
  if not ref then
    return nil, ref_err or "cannot resolve current git branch"
  end

  return { root = root, project = project, ref = ref }, nil
end

return M
