local M = {}

M.options = {
  glab_binary = "glab",
  gitlab_token_env = "GITLAB_TOKEN",
  default_branch = "main",
  ci_file = ".gitlab-ci.yml",
  picker = "vim_ui",
  scratch_height = 15,
}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
