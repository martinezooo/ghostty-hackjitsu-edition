-- Bootstrap lazy.nvim and LazyVim. Adapted from LazyVim/starter (Apache-2.0).
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local command = {
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  }
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({ { "Unable to install lazy.nvim:\n" .. output, "ErrorMsg" } }, true, {})
    return
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "plugins" },
  },
  defaults = { lazy = false, version = false },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = { enabled = true, notify = false },
})
