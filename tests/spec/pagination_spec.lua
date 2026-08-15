local runner = require("tests.runner")
local describe = runner.describe
local it = runner.it
local assert = runner.assert
local with_mock = runner.with_mock

local glab = require("gitlab.glab")
local api = require("gitlab.api")

-- Capture the path passed to glab.run_json; return a non-empty list so
-- latest_pipeline's post-call empty-check does not short-circuit before capture.
local function capture_path(fn)
  local path_seen
  with_mock(glab, "run_json", function(args)
    path_seen = args[2]
    return { { id = 1 } }, nil
  end, fn)
  return path_seen
end

describe("api.pipelines — query construction", function()
  it("uses per_page=20 by default", function()
    local path = capture_path(function()
      api.pipelines({})
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=20")
  end)

  it("uses custom per_page when specified", function()
    local path = capture_path(function()
      api.pipelines({ per_page = 50 })
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=50")
  end)

  it("appends &page when page > 0", function()
    local path = capture_path(function()
      api.pipelines({ page = 2 })
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=20&page=2")
  end)

  it("omits page when page is 0", function()
    local path = capture_path(function()
      api.pipelines({ page = 0 })
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=20")
  end)

  it("appends &ref when ref is present", function()
    local path = capture_path(function()
      api.pipelines({ ref = "main" })
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=20&ref=main")
  end)

  it("omits ref when ref is empty string", function()
    local path = capture_path(function()
      api.pipelines({ ref = "" })
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=20")
  end)

  it("preserves branch names with slashes in ref query", function()
    -- Slashes in branch names are kept verbatim in the query string;
    -- the API accepts them as-is without percent-encoding.
    local path = capture_path(function()
      api.pipelines({ ref = "feature/my-branch" })
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=20&ref=feature/my-branch")
  end)

  it("combines per_page, page, and ref", function()
    local path = capture_path(function()
      api.pipelines({ per_page = 10, page = 3, ref = "main" })
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=10&page=3&ref=main")
  end)
end)

describe("api.latest_pipeline — query construction", function()
  it("always uses per_page=1", function()
    local path = capture_path(function()
      api.latest_pipeline({})
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=1")
  end)

  it("appends &ref when ref is present", function()
    local path = capture_path(function()
      api.latest_pipeline({ ref = "main" })
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=1&ref=main")
  end)

  it("omits ref when ref is absent", function()
    local path = capture_path(function()
      api.latest_pipeline({})
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=1")
  end)

  it("omits ref when ref is empty string", function()
    local path = capture_path(function()
      api.latest_pipeline({ ref = "" })
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=1")
  end)
end)

describe("required ID validation", function()
  it("api.pipeline returns error when pipeline_id is nil", function()
    local result, err = api.pipeline(nil, {})
    assert.is_nil(result)
    assert.eq(err, "pipeline_id is required")
  end)

  it("api.pipeline_jobs returns error when pipeline_id is nil", function()
    local result, err = api.pipeline_jobs(nil, {})
    assert.is_nil(result)
    assert.eq(err, "pipeline_id is required")
  end)

  it("api.job returns error when job_id is nil", function()
    local result, err = api.job(nil, {})
    assert.is_nil(result)
    assert.eq(err, "job_id is required")
  end)
end)
