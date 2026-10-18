-- Hack-Jitsu's Tree-sitter installation policy for LazyVim.
--
-- LazyVim auto-installs opts.ensure_installed during Neovim startup and also
-- triggers TS.update from the plugin's build hook. Concurrent headless
-- bootstrap + those background installs can clone/rename the SAME cache paths,
-- causing ENOTEMPTY and "Failed to compile parser".
--
-- The installer explicitly downloads/compiles/loads all required grammars via
-- config/bootstrap.lua. Keep normal file-opening free of background installs.
-- For additional languages/updates users may run :TSInstall <lang> or :TSUpdate.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = false,
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
  },
}
