local M = {}

M.options = {
  glab_binary = "glab",
  gitlab_token_env = "GITLAB_TOKEN",
  ci_file = ".gitlab-ci.yml",
  picker = "vim_ui",
  scratch_height = 15,
  artifacts_dir = "gitlab-artifacts",
  extract_artifacts = true,
  notification = {},
}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
