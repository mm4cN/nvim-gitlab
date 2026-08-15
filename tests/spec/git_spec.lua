local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local git = require("gitlab.git")
local process = require("gitlab.util.process")

-- remote_project() calls M.remote_url() via the module table, so mocking
-- git.remote_url is sufficient to test the URL parsing logic in isolation.
describe("git.remote_project", function()
  local function with_url(url, fn)
    with_mock(git, "remote_url", function() return url, nil end, fn)
  end

  it("parses SSH remote", function()
    with_url("git@gitlab.com:namespace/project.git", function()
      local project, err = git.remote_project()
      assert.eq(project, "namespace/project")
      assert.is_nil(err)
    end)
  end)

  it("parses HTTPS remote", function()
    with_url("https://gitlab.com/namespace/project.git", function()
      local project, err = git.remote_project()
      assert.eq(project, "namespace/project")
      assert.is_nil(err)
    end)
  end)

  it("parses HTTP remote", function()
    with_url("http://gitlab.example.com/namespace/project.git", function()
      local project, err = git.remote_project()
      assert.eq(project, "namespace/project")
      assert.is_nil(err)
    end)
  end)

  it("parses ssh:// remote with slash separator", function()
    with_url("ssh://git@gitlab.com/namespace/project.git", function()
      local project, err = git.remote_project()
      assert.eq(project, "namespace/project")
      assert.is_nil(err)
    end)
  end)
  -- Note: ssh://git@host:path (colon separator) is not currently supported;
  -- the pattern's [^/]+ greedily consumes the colon as part of the host.
  -- Fixing that is a separate production-code concern outside Phase 2 scope.

  it("strips .git suffix", function()
    with_url("git@gitlab.com:namespace/project.git", function()
      local project = git.remote_project()
      assert.eq(project, "namespace/project")
    end)
  end)

  it("works without .git suffix", function()
    with_url("git@gitlab.com:namespace/project", function()
      local project, err = git.remote_project()
      assert.eq(project, "namespace/project")
      assert.is_nil(err)
    end)
  end)

  it("preserves nested namespaces", function()
    with_url("git@gitlab.com:group/subgroup/project.git", function()
      local project, err = git.remote_project()
      assert.eq(project, "group/subgroup/project")
      assert.is_nil(err)
    end)
  end)

  it("works with a custom GitLab host", function()
    with_url("git@gitlab.internal:namespace/project.git", function()
      local project, err = git.remote_project()
      assert.eq(project, "namespace/project")
      assert.is_nil(err)
    end)
  end)

  it("returns nil and error for an unrecognised remote format", function()
    with_url("ftp://somewhere/stuff", function()
      local project, err = git.remote_project()
      assert.is_nil(project)
      assert.not_nil(err)
      assert.contains(err, "Cannot extract project path from remote")
    end)
  end)

  it("propagates remote_url failure", function()
    with_mock(git, "remote_url", function() return nil, "Cannot detect origin remote" end, function()
      local project, err = git.remote_project()
      assert.is_nil(project)
      assert.eq(err, "Cannot detect origin remote")
    end)
  end)
end)

-- root() and branch() call process.run directly.
describe("git.root", function()
  it("returns the repo root on success", function()
    with_mock(process, "run", function() return "/home/user/repo", nil end, function()
      local root, err = git.root()
      assert.eq(root, "/home/user/repo")
      assert.is_nil(err)
    end)
  end)

  it("returns nil and error when not in a git repository", function()
    with_mock(process, "run", function() return nil, "fatal: not a git repository" end, function()
      local root, err = git.root()
      assert.is_nil(root)
      assert.eq(err, "Not inside a git repository")
    end)
  end)
end)

describe("git.branch", function()
  it("returns the current branch name on success", function()
    with_mock(process, "run", function() return "main", nil end, function()
      local branch, err = git.branch()
      assert.eq(branch, "main")
      assert.is_nil(err)
    end)
  end)

  it("returns nil and error when git branch fails", function()
    with_mock(process, "run", function() return nil, "fatal: not a git repository" end, function()
      local branch, err = git.branch()
      assert.is_nil(branch)
      assert.eq(err, "Cannot detect current branch")
    end)
  end)

  it("returns nil and error for detached HEAD", function()
    with_mock(process, "run", function() return "", nil end, function()
      local branch, err = git.branch()
      assert.is_nil(branch)
      assert.eq(err, "Detached HEAD is not supported yet")
    end)
  end)
end)
