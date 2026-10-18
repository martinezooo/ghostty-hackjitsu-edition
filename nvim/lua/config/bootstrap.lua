-- Hack-Jitsu: explicit parser installation in TWO independent Neovim sessions.
-- HJ_TS_BUILD_ONLY=1: compile parsers synchronously, do not try to load new
-- parser binaries in the SAME process (Neovim 0.11 can return nil for them).
-- HJ_TS_VERIFY_ONLY=1: a fresh Neovim process validates parser loading.
--
-- LazyVim's auto-ensure and background plugin build hook are disabled by
-- plugins/hj-treesitter-policy.lua to avoid simultaneous cache renames.
local function fail(message)
  io.stderr:write("\nHJ_NVIM_BOOTSTRAP_FAILED: " .. message .. "\n")
  vim.cmd("cquit 1")
end

local verify_only = vim.env.HJ_TS_VERIFY_ONLY == "1"
if not verify_only then
  if vim.fn.executable("tree-sitter") ~= 1 then
    fail("Missing tree-sitter-cli. Fix: brew install tree-sitter-cli")
    return
  end
  if vim.fn.executable("cc") ~= 1 then
    fail("Missing C compiler. Fix: xcode-select --install")
    return
  end
end

local ok, ts = pcall(require, "nvim-treesitter")
if not ok or type(ts.get_installed) ~= "function" then
  fail("nvim-treesitter is unavailable or incompatible. Run :Lazy sync and retry.")
  return
end

local required = {
  "bash", "c", "diff", "html", "javascript", "jsdoc", "json", "lua",
  "luadoc", "luap", "markdown", "markdown_inline", "printf", "python",
  "query", "regex", "toml", "tsx", "typescript", "vim", "vimdoc", "xml", "yaml",
}

if not verify_only then
  if type(ts.install) ~= "function" then
    fail("nvim-treesitter install API is unavailable")
    return
  end
  local started, task = pcall(ts.install, required)
  if not started or not task or type(task.wait) ~= "function" then
    fail("Parser build did not start: " .. tostring(task))
    return
  end
  local finished, err = pcall(function()
    task:wait(240000)
  end)
  if not finished then
    fail("Parser compilation failed/timed out: " .. tostring(err))
    return
  end
end

local installed = {}
for _, parser in ipairs(ts.get_installed()) do
  installed[parser] = true
end
local missing = {}
for _, parser in ipairs(required) do
  if not installed[parser] then
    table.insert(missing, parser)
  end
end
if #missing > 0 then
  fail("Parser " .. (verify_only and "verification" or "compilation")
       .. " incomplete; missing: " .. table.concat(missing, ", "))
  return
end

if verify_only then
  local broken = {}
  for _, parser in ipairs(required) do
    local works, loaded = pcall(vim.treesitter.language.add, parser)
    if not works or loaded ~= true then
      table.insert(broken, parser .. ": " .. tostring(loaded))
    end
  end
  if #broken > 0 then
    fail("Compiled parsers failed to load in NEW Neovim process: "
         .. table.concat(broken, "; "))
    return
  end
  print(("HJ_NVIM_BOOTSTRAP_READY: verified %d parsers in fresh Neovim process"):format(#required))
else
  print(("HJ_NVIM_BOOTSTRAP_BUILT: compiled %d parsers"):format(#required))
end
vim.cmd("qa!")
