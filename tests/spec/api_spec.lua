local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local glab = require("gitlab.glab")
local api = require("gitlab.api")

-- Most API functions reach glab.run_json via M.request; the path is args[2].
-- pipeline_inputs reaches glab.run directly; the path is still args[2].
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

describe("api.run_pipeline", function()
  it("uses encoded explicit project in path", function()
    local path = capture_path_json(function()
      api.run_pipeline({ project = "ns/proj", ref = "main" })
    end)
    assert.eq(path, "projects/ns%2Fproj/pipeline")
  end)

  it("uses :id when project is absent", function()
    local path = capture_path_json(function()
      api.run_pipeline({ ref = "main" })
    end)
    assert.eq(path, "projects/:id/pipeline")
  end)
end)

describe("api.pipeline_inputs", function()
  it("uses encoded explicit project in path", function()
    local path = capture_path_run(function()
      api.pipeline_inputs({ project = "ns/proj", ref = "main" })
    end)
    assert.eq(path, "projects/ns%2Fproj/repository/files/.gitlab-ci.yml/raw?ref=main")
  end)

  it("uses :id when project is absent", function()
    local path = capture_path_run(function()
      api.pipeline_inputs({ ref = "main" })
    end)
    assert.eq(path, "projects/:id/repository/files/.gitlab-ci.yml/raw?ref=main")
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
