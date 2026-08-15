local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local git = require("gitlab.git")
local context = require("gitlab.ci.context")

-- context.from_cwd() calls git.root, git.remote_project, git.branch via
-- its upvalue git table, so mocking those functions in place is sufficient.

-- with_git stacks three with_mock calls so all three git functions are
-- restored even when fn throws.
local function with_git(root_fn, proj_fn, branch_fn, fn)
  with_mock(git, "root", root_fn, function()
    with_mock(git, "remote_project", proj_fn, function()
      with_mock(git, "branch", branch_fn, fn)
    end)
  end)
end

local function ok_root()    return "/repo", nil end
local function ok_project() return "group/project", nil end
local function ok_branch()  return "main", nil end

describe("context.from_cwd", function()
  it("returns a complete context on success", function()
    with_git(ok_root, ok_project, ok_branch, function()
      local ctx, err = context.from_cwd()
      assert.is_nil(err)
      assert.not_nil(ctx)
      assert.eq(ctx.root, "/repo")
      assert.eq(ctx.project, "group/project")
      assert.eq(ctx.ref, "main")
    end)
  end)

  it("returns nil and error when root cannot be resolved", function()
    with_git(
      function() return nil, "Not inside a git repository" end,
      ok_project, ok_branch,
      function()
        local ctx, err = context.from_cwd()
        assert.is_nil(ctx)
        assert.eq(err, "Not inside a git repository")
      end
    )
  end)

  it("returns nil and error when project cannot be resolved", function()
    with_git(
      ok_root,
      function() return nil, "Cannot detect origin remote" end,
      ok_branch,
      function()
        local ctx, err = context.from_cwd()
        assert.is_nil(ctx)
        assert.eq(err, "Cannot detect origin remote")
      end
    )
  end)

  it("returns nil and error when ref cannot be resolved", function()
    with_git(
      ok_root, ok_project,
      function() return nil, "Detached HEAD is not supported yet" end,
      function()
        local ctx, err = context.from_cwd()
        assert.is_nil(ctx)
        assert.eq(err, "Detached HEAD is not supported yet")
      end
    )
  end)

  it("does not return a partial context when root fails", function()
    with_git(
      function() return nil, "Not inside a git repository" end,
      ok_project, ok_branch,
      function()
        local ctx, err = context.from_cwd()
        assert.is_nil(ctx)
        assert.not_nil(err)
      end
    )
  end)

  it("does not return a partial context when project fails", function()
    with_git(
      ok_root,
      function() return nil, "Cannot extract project path from remote: ftp://x" end,
      ok_branch,
      function()
        local ctx, err = context.from_cwd()
        assert.is_nil(ctx)
        assert.not_nil(err)
      end
    )
  end)

  it("does not return a partial context when ref fails", function()
    with_git(
      ok_root, ok_project,
      function() return nil, "Cannot detect current branch" end,
      function()
        local ctx, err = context.from_cwd()
        assert.is_nil(ctx)
        assert.not_nil(err)
      end
    )
  end)

  it("uses the error message from git.root when it provides one", function()
    with_git(
      function() return nil, "custom root error" end,
      ok_project, ok_branch,
      function()
        local ctx, err = context.from_cwd()
        assert.is_nil(ctx)
        assert.eq(err, "custom root error")
      end
    )
  end)
end)
