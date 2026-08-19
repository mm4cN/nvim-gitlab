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

  it("percent-encodes slashes in branch names in ref query", function()
    -- rfc2396 encoding percent-encodes '/' along with other reserved characters.
    local path = capture_path(function()
      api.pipelines({ ref = "feature/my-branch" })
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=20&ref=feature%2fmy-branch")
  end)

  it("combines per_page, page, and ref", function()
    local path = capture_path(function()
      api.pipelines({ per_page = 10, page = 3, ref = "main" })
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=10&page=3&ref=main")
  end)

  it("URL-encodes '&' and '=' in ref so they cannot be mistaken for query separators", function()
    local path = capture_path(function()
      api.pipelines({ ref = "feature/fix & cleanup=1" })
    end)
    local expected_ref = vim.uri_encode("feature/fix & cleanup=1", "rfc2396")
    assert.eq(path, "projects/:id/pipelines?per_page=20&ref=" .. expected_ref)
    local query = path:match("&ref=(.*)$")
    assert.is_nil(query:find("&", 1, true))
    assert.is_nil(query:find("=", 1, true))
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

  it("URL-encodes '&' and '=' in ref so they cannot be mistaken for query separators", function()
    local path = capture_path(function()
      api.latest_pipeline({ ref = "feature/fix & cleanup=1" })
    end)
    local expected_ref = vim.uri_encode("feature/fix & cleanup=1", "rfc2396")
    assert.eq(path, "projects/:id/pipelines?per_page=1&ref=" .. expected_ref)
    local query = path:match("&ref=(.*)$")
    assert.is_nil(query:find("&", 1, true))
    assert.is_nil(query:find("=", 1, true))
  end)
end)

describe("api.latest_pipeline_async — query construction", function()
  local function capture_path_async(fn)
    local path_seen
    with_mock(glab, "run_json_async", function(args, _opts, callback)
      path_seen = args[2]
      callback({ { id = 1 } }, nil)
    end, fn)
    return path_seen
  end

  it("appends &ref when ref is present", function()
    local path = capture_path_async(function()
      api.latest_pipeline_async({ ref = "main" }, function() end)
    end)
    assert.eq(path, "projects/:id/pipelines?per_page=1&ref=main")
  end)

  it("URL-encodes '&' and '=' in ref so they cannot be mistaken for query separators", function()
    local path = capture_path_async(function()
      api.latest_pipeline_async({ ref = "feature/fix & cleanup=1" }, function() end)
    end)
    local expected_ref = vim.uri_encode("feature/fix & cleanup=1", "rfc2396")
    assert.eq(path, "projects/:id/pipelines?per_page=1&ref=" .. expected_ref)
    local query = path:match("&ref=(.*)$")
    assert.is_nil(query:find("&", 1, true))
    assert.is_nil(query:find("=", 1, true))
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
