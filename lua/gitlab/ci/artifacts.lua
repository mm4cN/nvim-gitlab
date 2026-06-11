local api = require("gitlab.api")
local auth = require("gitlab.auth")
local config = require("gitlab.config")
local git = require("gitlab.git")
local buffer = require("gitlab.ui.buffer")
local notification = require("gitlab.ui.notification")
local process = require("gitlab.util.process")

local M = {}

local function repo_root()
  local root, err = git.root()

  if not root then
    notification.error(err)
    return nil
  end

  return root
end

local function default_output_dir()
  return vim.fn.getcwd() .. "/" .. config.options.artifacts_dir
end

local function ensure_dir(path)
  if vim.fn.isdirectory(path) == 1 then
    return true
  end

  return vim.fn.mkdir(path, "p") == 1
end

local function artifact_path(output_dir, job_id)
  return output_dir .. "/job-" .. tostring(job_id) .. "-artifacts.zip"
end

local function artifact_url(project_id, job_id)
  return "https://gitlab.com/api/v4/projects/"
      .. tostring(project_id)
      .. "/jobs/"
      .. tostring(job_id)
      .. "/artifacts"
end

function M.download(opts)
  opts = opts or {}

  local job_id = opts.job_id

  if not job_id or job_id == "" then
    notification.error("job_id is required")
    return
  end

  local root = repo_root()
  if not root then
    return
  end

  local token, token_err = auth.token()
  if not token then
    notification.error(token_err)
    return
  end

  local project, project_err = api.get("projects/:id", {
    cwd = root,
  })

  if not project then
    notification.error(project_err)
    return
  end

  local output_dir = opts.output_dir or default_output_dir()

  if not ensure_dir(output_dir) then
    notification.error("Cannot create artifacts directory: " .. output_dir)
    return
  end

  local output_path = artifact_path(output_dir, job_id)
  local url = artifact_url(project.id, job_id)

  notification.info("Downloading artifacts for job " .. tostring(job_id) .. "...")

  local _, err = process.run({
    "curl",
    "--fail",
    "--location",
    "--silent",
    "--show-error",
    "--header",
    "PRIVATE-TOKEN: " .. token,
    url,
    "--output",
    output_path,
  }, {
    cwd = root,
  })

  if err then
    notification.error(err)
    return
  end

  notification.info("Artifacts downloaded: " .. output_path)

  local extract_dir = nil
  if config.options.extract_artifacts then
    extract_dir = output_dir .. "/job-" .. tostring(job_id)
    ensure_dir(extract_dir)
    local _, unzip_err = process.run({
      "unzip",
      "-o",
      output_path,
      "-d",
      extract_dir,
    }, {
      cwd = root,
    })

    if unzip_err then
      notification.error(unzip_err)
      return
    end
  end

  local lines = {
    "Artifacts downloaded",
    "",
    "Job:     " .. tostring(job_id),
    "Archive: " .. output_path,
  }

  if extract_dir then
    table.insert(lines, "Extracted: " .. extract_dir)
  end

  local hints = {
    { key = "b", label = "Back" },
    { key = "q", label = "Quit" },
  }

  buffer.push({
    title = "GitLab Artifacts",
    filetype = "gitlab",
    lines = lines,
    hints = hints,
    keymaps = {
      q = buffer.close_current,
      b = buffer.back,
    },
  })
end

return M
