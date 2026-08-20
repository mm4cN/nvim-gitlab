local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local glab = require("gitlab.glab")
local api = require("gitlab.api")

-- Most API functions reach glab.run_json via M.request; the path is args[2].
-- pipeline_inputs also uses M.get (→ glab.run_json) against the ci/lint endpoint.
-- Path is captured before any post-processing, so the mock return value only
-- needs to satisfy the function's minimum requirements to avoid an early error.

local function capture_path_json(fn)
  local path_seen
  with_mock(glab, "run_json", function(args)
    path_seen = args[2]
    return {}, nil
  end, fn)
  return path_seen
end

local function capture_path_run(fn)
  local path_seen
  with_mock(glab, "run", function(args)
    path_seen = args[2]
    return "# fixture", nil
  end, fn)
  return path_seen
end

-- latest_pipeline checks #pipelines == 0 after the glab call.
-- Return a non-empty list so the path is the only failure point in tests
-- that care about the return value; for path-only tests the early return is fine.
local function capture_path_json_with_list(fn)
  local path_seen
  with_mock(glab, "run_json", function(args)
    path_seen = args[2]
    return { { id = 1 } }, nil
  end, fn)
  return path_seen
end

describe("api.pipelines", function()
  it("uses encoded explicit project in path", function()
    local path = capture_path_json(function()
      api.pipelines({ project = "ns/proj" })
    end)
    assert.eq(path, "projects/ns%2Fproj/pipelines?per_page=20")
  end)

  it("uses :id when project is absent", function()
    local path = capture_path_json(function()
      api.pipelines({})
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=20")
  end)
end)

describe("api.project", function()
  it("uses the encoded project path and returns normalized metadata", function()
    local path_seen
    local result
    with_mock(glab, "run_json", function(args)
      path_seen = args[2]
      return {
        id = 42,
        name = "project",
        path_with_namespace = "group/sub/project",
        default_branch = "trunk",
        description = "not part of the normalized result",
      }, nil
    end, function()
      result = api.project({ project = "group/sub/project", cwd = "/repo" })
    end)
    assert.eq(path_seen, "projects/group%2Fsub%2Fproject")
    assert.eq(result.id, 42)
    assert.eq(result.name, "project")
    assert.eq(result.path_with_namespace, "group/sub/project")
    assert.eq(result.default_branch, "trunk")
    assert.is_nil(result.description)
  end)

  it("requires an explicit project without making a request", function()
    local called = false
    with_mock(glab, "run_json", function()
      called = true
      return {}, nil
    end, function()
      local result, err = api.project({})
      assert.is_nil(result)
      assert.eq(err, "project is required")
    end)
    assert.eq(called, false)
  end)

  it("propagates inaccessible-project errors", function()
    with_mock(glab, "run_json", function() return nil, "404 Project Not Found" end, function()
      local result, err = api.project({ project = "private/project" })
      assert.is_nil(result)
      assert.eq(err, "404 Project Not Found")
    end)
  end)

  it("rejects incomplete project metadata", function()
    with_mock(glab, "run_json", function()
      return { id = 42, name = "project", path_with_namespace = "group/project" }, nil
    end, function()
      local result, err = api.project({ project = "group/project" })
      assert.is_nil(result)
      assert.contains(err, "default_branch")
    end)
  end)

  it("requires id and name in the normalized metadata contract", function()
    with_mock(glab, "run_json", function()
      return { name = "project", path_with_namespace = "group/project", default_branch = "main" }, nil
    end, function()
      local result, err = api.project({ project = "group/project" })
      assert.is_nil(result)
      assert.contains(err, "id")
    end)
    with_mock(glab, "run_json", function()
      return { id = 42, path_with_namespace = "group/project", default_branch = "main" }, nil
    end, function()
      local result, err = api.project({ project = "group/project" })
      assert.is_nil(result)
      assert.contains(err, "name")
    end)
  end)
end)

describe("api.projects", function()
  it("lists membership projects in activity order and normalizes entries", function()
    local paths = {}
    local projects
    with_mock(glab, "run_json", function(args)
      table.insert(paths, args[2])
      if #paths == 1 then
        return {
          {
            id = 1, name = "one", path_with_namespace = "group/one",
            default_branch = "main", last_activity_at = "2026-08-20",
          },
          {
            id = 2, name = "empty", path_with_namespace = "group/empty",
            default_branch = vim.NIL,
          },
        }, nil
      end
      return {}, nil
    end, function()
      projects = api.projects({ per_page = 2, max_pages = 3, cwd = "/repo" })
    end)
    assert.contains(paths[1], "membership=true")
    assert.contains(paths[1], "order_by=last_activity_at")
    assert.contains(paths[1], "per_page=2&page=1")
    assert.contains(paths[2], "per_page=2&page=2")
    assert.eq(#paths, 2)
    assert.eq(#projects, 2)
    assert.eq(projects[1].path_with_namespace, "group/one")
    assert.eq(projects[1].default_branch, "main")
    assert.eq(projects[2].default_branch, "")
  end)

  it("stops after a short page", function()
    local calls = 0
    with_mock(glab, "run_json", function()
      calls = calls + 1
      return {
        { id = 1, name = "one", path_with_namespace = "group/one", default_branch = "main" },
      }, nil
    end, function()
      local projects = api.projects({ per_page = 100, max_pages = 3 })
      assert.eq(#projects, 1)
    end)
    assert.eq(calls, 1)
  end)

  it("propagates pagination failures without returning partial results", function()
    local calls = 0
    with_mock(glab, "run_json", function()
      calls = calls + 1
      if calls == 1 then
        return {
          { id = 1, name = "one", path_with_namespace = "group/one", default_branch = "main" },
        }, nil
      end
      return nil, "forbidden"
    end, function()
      local projects, err = api.projects({ per_page = 1, max_pages = 2 })
      assert.is_nil(projects)
      assert.eq(err, "forbidden")
    end)
  end)
end)

describe("api.latest_pipeline", function()
  it("uses encoded explicit project in path", function()
    local path = capture_path_json_with_list(function()
      api.latest_pipeline({ project = "ns/proj" })
    end)
    assert.eq(path, "projects/ns%2Fproj/pipelines?per_page=1")
  end)

  it("uses :id when project is absent", function()
    local path = capture_path_json_with_list(function()
      api.latest_pipeline({})
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=1")
  end)
end)

describe("api.pipeline", function()
  it("uses encoded explicit project in path", function()
    local path = capture_path_json(function()
      api.pipeline(42, { project = "ns/proj" })
    end)
    assert.eq(path, "projects/ns%2Fproj/pipelines/42")
  end)

  it("uses :id when project is absent", function()
    local path = capture_path_json(function()
      api.pipeline(42, {})
    end)
    assert.eq(path, "projects/:id/pipelines/42")
  end)

  it("does not fall back to :id when an explicit project request fails", function()
    local path_seen
    local call_count = 0
    with_mock(glab, "run_json", function(args)
      path_seen = args[2]
      call_count = call_count + 1
      return nil, "forbidden"
    end, function()
      api.pipeline(42, { project = "ns/proj" })
    end)
    assert.eq(call_count, 1)
    assert.eq(path_seen, "projects/ns%2Fproj/pipelines/42")
  end)
end)

describe("api.pipeline_jobs", function()
  it("uses encoded explicit project in path", function()
    local path = capture_path_json(function()
      api.pipeline_jobs(42, { project = "ns/proj" })
    end)
    assert.eq(path, "projects/ns%2Fproj/pipelines/42/jobs")
  end)

  it("uses :id when project is absent", function()
    local path = capture_path_json(function()
      api.pipeline_jobs(42, {})
    end)
    assert.eq(path, "projects/:id/pipelines/42/jobs")
  end)
end)

describe("api.job", function()
  it("uses encoded explicit project in path", function()
    local path = capture_path_json(function()
      api.job(7, { project = "ns/proj" })
    end)
    assert.eq(path, "projects/ns%2Fproj/jobs/7")
  end)

  it("uses :id when project is absent", function()
    local path = capture_path_json(function()
      api.job(7, {})
    end)
    assert.eq(path, "projects/:id/jobs/7")
  end)
end)

describe("api.pipeline_inputs", function()
  -- pipeline_inputs calls glab.run for the raw CI file (primary) and
  -- glab.run_json for ci/lint merged_yaml (secondary). Both paths are tested.
  local function capture_both_paths(fn)
    local raw_path, lint_path
    with_mock(glab, "run", function(args)
      raw_path = args[2]
      return "# fixture", nil
    end, function()
      with_mock(glab, "run_json", function(args)
        lint_path = args[2]
        return { merged_yaml = "# fixture" }, nil
      end, fn)
    end)
    return raw_path, lint_path
  end

  it("fetches raw CI file with encoded project and ref", function()
    local raw_path = capture_both_paths(function()
      api.pipeline_inputs({ project = "ns/proj", ref = "main" })
    end)
    assert.eq(raw_path, "projects/ns%2Fproj/repository/files/.gitlab-ci.yml/raw?ref=main")
  end)

  it("fetches ci/lint with encoded project and content_ref", function()
    local _, lint_path = capture_both_paths(function()
      api.pipeline_inputs({ project = "ns/proj", ref = "main" })
    end)
    assert.eq(lint_path, "projects/ns%2Fproj/ci/lint?content_ref=main")
  end)

  it("uses :id when project is absent", function()
    local raw_path, lint_path = capture_both_paths(function()
      api.pipeline_inputs({ ref = "main" })
    end)
    assert.eq(raw_path, "projects/:id/repository/files/.gitlab-ci.yml/raw?ref=main")
    assert.eq(lint_path, "projects/:id/ci/lint?content_ref=main")
  end)

  it("URL-encodes '&' and '=' in ref so they cannot be mistaken for query separators", function()
    local raw_path, lint_path = capture_both_paths(function()
      api.pipeline_inputs({ project = "ns/proj", ref = "feature/fix & cleanup=1" })
    end)
    local expected_ref = vim.uri_encode("feature/fix & cleanup=1", "rfc2396")
    assert.eq(raw_path, "projects/ns%2Fproj/repository/files/.gitlab-ci.yml/raw?ref=" .. expected_ref)
    assert.eq(lint_path, "projects/ns%2Fproj/ci/lint?content_ref=" .. expected_ref)

    local raw_query = raw_path:match("%?ref=(.*)$")
    assert.is_nil(raw_query:find("&", 1, true))
    assert.is_nil(raw_query:find("=", 1, true))

    local lint_query = lint_path:match("%?content_ref=(.*)$")
    assert.is_nil(lint_query:find("&", 1, true))
    assert.is_nil(lint_query:find("=", 1, true))
  end)
end)

describe("api.branches", function()
  it("uses encoded explicit project in path", function()
    local path = capture_path_json(function()
      api.branches({ project = "ns/proj" })
    end)
    assert.eq(path, "projects/ns%2Fproj/repository/branches?per_page=100")
  end)

  it("returns error without calling glab when project is absent", function()
    local glab_called = false
    with_mock(glab, "run_json", function()
      glab_called = true
      return {}, nil
    end, function()
      local result, err = api.branches({})
      assert.is_nil(result)
      assert.eq(err, "project is required")
    end)
    assert.eq(glab_called, false)
  end)
end)

describe("api.variables", function()
  it("uses encoded explicit project in path with per_page=100", function()
    local path = capture_path_json(function()
      api.variables({ project = "ns/proj" })
    end)
    assert.eq(path, "projects/ns%2Fproj/variables?per_page=100")
  end)

  it("uses :id when project is absent", function()
    local path = capture_path_json(function()
      api.variables({})
    end)
    assert.eq(path, "projects/:id/variables?per_page=100")
  end)

  it("returns raw API data without domain-level filtering", function()
    local result
    with_mock(glab, "run_json", function()
      return {
        { key = "A", value = "1", description = "has description" },
        { key = "B", value = "2", description = "" },
        { key = "C", value = "3" },
      }, nil
    end, function()
      result, _ = api.variables({ project = "ns/proj" })
    end)
    assert.eq(#result, 3)
    assert.eq(result[2].key, "B")
    assert.eq(result[3].key, "C")
  end)
end)

describe("nested namespace encoding", function()
  it("encodes every slash in a multi-level namespace", function()
    local path = capture_path_json(function()
      api.pipelines({ project = "group/sub/project" })
    end)
    assert.eq(path, "projects/group%2Fsub%2Fproject/pipelines?per_page=20")
  end)
end)
