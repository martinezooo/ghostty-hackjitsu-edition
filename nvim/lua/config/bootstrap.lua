-- Hack-Jitsu: verify actual parser compilation before claiming LazyVim is ready.
-- Executed explicitly in a headless bootstrap session, never on every file open.
local function fail(message)
  io.stderr:write("\nHJ_NVIM_BOOTSTRAP_FAILED: " .. message .. "\n")
  vim.cmd("cquit 1")
end

if vim.fn.executable("tree-sitter") ~= 1 then
  fail("Missing tree-sitter-cli. Fix: brew install tree-sitter-cli")
  return
end
if vim.fn.executable("cc") ~= 1 then
  fail("Missing C compiler. Fix: xcode-select --install")
  return
end

local ok, ts = pcall(require, "nvim-treesitter")
if not ok or type(ts.install) ~= "function" or type(ts.get_installed) ~= "function" then
  fail("nvim-treesitter is unavailable or incompatible. Run :Lazy sync and retry.")
  return
end

-- Essential LazyVim syntax highlighters, installed during setup instead
-- of unexpectedly when the user's first log, JSON or source file is opened.
local required = {
  "bash", "c", "diff", "html", "javascript", "jsdoc", "json", "lua",
  "luadoc", "luap", "markdown", "markdown_inline", "printf", "python",
  "query", "regex", "toml", "tsx", "typescript", "vim", "vimdoc", "xml", "yaml",
}
local started, task = pcall(ts.install, required)
if not started or not task or type(task.wait) ~= "function" then
  fail("Parser installation could not start: " .. tostring(task))
  return
end
local finished, err = pcall(function()
  task:wait(240000)
end)
if not finished then
  fail("Parser installation failed/timed out: " .. tostring(err))
  return
end

local installed = {}
for _, parser in ipairs(ts.get_installed()) do
  installed[parser] = true
end
local missing = {}
for _, parser in ipairs(required) do
  if not installed[parser] then table.insert(missing, parser) end
end
if #missing > 0 then
  fail("Parser compilation incomplete; missing: " .. table.concat(missing, ", "))
  return
end

-- A compiled .so is not enough; confirm all parser binaries can be loaded
-- by the actual Neovim runtime before the installer reports a successful setup.
local broken = {}
for _, parser in ipairs(required) do
  local works, result = pcall(vim.treesitter.language.add, parser)
  if not works or result ~= true then
    table.insert(broken, parser .. ": " .. tostring(result))
  end
end
if #broken > 0 then
  fail("Compiled parsers failed to load: " .. table.concat(broken, "; "))
  return
end

print(("HJ_NVIM_BOOTSTRAP_READY: verified %d parsers with tree-sitter-cli"):format(#required))
vim.cmd("qa!")
