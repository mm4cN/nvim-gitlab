if vim.g.loaded_gitlab_nvim then
  return
end

vim.g.loaded_gitlab_nvim = true

require("gitlab.commands").setup()
