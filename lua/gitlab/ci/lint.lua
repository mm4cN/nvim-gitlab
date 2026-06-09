local config = require("gitlab.config")
local git = require("gitlab.git")
local glab = require("gitlab.glab")
local buffer = require("gitlab.ui.buffer")
local notification = require("gitlab.ui.notification")

local M = {}

function M.validate()
  local root, root_err = git.root()
  if not root then
    notification.error(root_err)
    return
  end

  local ci_file = config.options.ci_file
  local ci_path = root .. "/" .. ci_file

  if vim.fn.filereadable(ci_path) ~= 1 then
    notification.error("Cannot find " .. ci_file)
    return
  end

  local output, err = glab.run({
    "ci",
    "lint",
    ci_file,
  }, {
    cwd = root,
  })

  if err then
    buffer.show({
      title = "GitLab CI Lint",
      filetype = "text",
      lines = vim.split(err, "\n", { plain = true }),
    })
    return
  end

  buffer.show({
    title = "GitLab CI Lint",
    filetype = "text",
    lines = vim.split(output, "\n", { plain = true }),
  })
end

return M
