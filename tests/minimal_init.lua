-- Minimal Neovim init for headless test runs.
-- Prepends the plugin root to runtimepath so plugin modules can be required.
-- Does not load any user config or other plugins.
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(vim.fn.expand("<sfile>"), ":h:h"))
