local api = require("gitlab.api")
local notification = require("gitlab.ui.notification")
local picker = require("gitlab.ui.picker")

local M = {}

function M.select(opts, callback)
  opts = opts or {}
  callback = callback or function() end

  local projects, err = api.projects({
    cwd = opts.cwd,
    per_page = opts.per_page,
    max_pages = opts.max_pages,
  })
  if not projects then
    notification.error("Could not fetch projects: " .. tostring(err))
    callback(nil)
    return
  end
  if #projects == 0 then
    notification.warn("No accessible projects found")
    callback(nil)
    return
  end

  picker.select(projects, {
    prompt = opts.prompt or "Select GitLab project",
    select_label = "Select project",
    format_item = function(project)
      return project.path_with_namespace
    end,
    preview = function(project)
      return {
        "Project",
        string.rep("─", 12),
        "Name            " .. tostring(project.name),
        "Path            " .. tostring(project.path_with_namespace),
        "Default branch  " .. (project.default_branch ~= "" and project.default_branch or "(none)"),
        "Last activity   " .. tostring(project.last_activity_at or ""),
      }
    end,
  }, callback)
end

return M
