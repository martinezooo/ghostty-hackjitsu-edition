#!/usr/bin/env bash
# Built-in Neovim log view: hide ANSI colors, never silently edit forensic evidence.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v nvim >/dev/null 2>&1; then echo 'SKIP: no nvim'; exit 0; fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HJ_ANSI_TMP="$TMP" HJ_ANSI_ROOT="$ROOT"
python3 - <<'PYTHON'
import os,pathlib
p=pathlib.Path(os.environ['HJ_ANSI_TMP'])
(p/'ansi.log').write_text('start \x1b[31mRED\x1b[0m end\n'+'serialized \\x1b[32mGREEN\\x1b[0m \\u001b[34mBLUE\\u001b[0m\n'+'important literal \\x41 and \\x31 must survive\n')
(p/'plain.txt').write_text('plain and important \\x41\n')
PYTHON
cat > "$TMP/test.lua" <<'LUA'
local root, tmp = vim.env.HJ_ANSI_ROOT, vim.env.HJ_ANSI_TMP
package.path = root .. '/nvim/lua/?.lua;' .. package.path
-- Load the real Hack-Jitsu entrypoint while stubbing only network-heavy LazyVim.
package.loaded['config.lazy'] = true
dofile(root .. '/nvim/init.lua')
assert(vim.fn.exists(':HJAnsiToggle') == 2, 'init.lua did not enable commands')
local original = vim.fn.readfile(tmp .. '/ansi.log')
vim.cmd.edit(tmp .. '/ansi.log')
assert(vim.b.hj_ansi_conceal == true, 'ANSI buffer should auto conceal')
assert(vim.wo.conceallevel == 3, 'missing conceallevel=3')
assert(#(vim.w.hj_ansi_matches or {}) == 3, 'missing match rules')
-- Assert the actual Neovim regular expressions match real/log-escaped ANSI
-- text, not merely that matchadd returned three non-zero IDs.
local examples = {
  'real \27[31mRED',
  [[serialized \x1b[32mGREEN]],
  [[unicode \u001b[34mBLUE]],
}
for _, sample in ipairs(examples) do
  local matched = false
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.group == 'Conceal' and vim.fn.matchstr(sample, match.pattern) ~= '' then
      matched = true
      break
    end
  end
  assert(matched, 'no conceal regex matched: ' .. sample)
end

assert(vim.bo.modified == false, 'view must not edit evidence')
assert(vim.fn.getline(1) == original[1], 'buffer must preserve original bytes')
vim.cmd('HJAnsiToggle')
assert(vim.b.hj_ansi_conceal == false, 'toggle did not disable')
assert(#(vim.w.hj_ansi_matches or {}) == 0, 'match rules still enabled')
vim.cmd('HJAnsiToggle')
assert(vim.b.hj_ansi_conceal == true, 'toggle did not re-enable')
vim.cmd('HJAnsiStrip')
assert(vim.bo.modified == true, 'strip should mark buffer modified')
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(lines[1] == 'start RED end', 'real ANSI escape was not removed: ' .. lines[1])
assert(lines[2] == 'serialized GREEN BLUE', 'literal escapes were not removed: ' .. lines[2])
assert(lines[3] == 'important literal \\x41 and \\x31 must survive', 'non-color data changed')
assert(vim.fn.readfile(tmp .. '/ansi.log')[1] == original[1], 'disk was modified without write')
vim.cmd('undo')
assert(vim.fn.getline(1) == original[1], 'single undo did not restore file')
vim.cmd('HJAnsiStrip')
vim.cmd('write')
assert(vim.fn.readfile(tmp .. '/ansi.log')[1] == 'start RED end', 'explicit write did not persist cleaned log')
vim.cmd.edit(tmp .. '/plain.txt')
assert(vim.b.hj_ansi_conceal == false, 'plain files must not auto conceal')
assert(#(vim.w.hj_ansi_matches or {}) == 0, 'window still has matches from former buffer')
assert(vim.bo.modified == false, 'plain file unexpectedly modified')
assert(vim.wo.conceallevel == 0, 'conceallevel did not restore on plain file')

print('PASS: auto conceal ANSI SGR, toggle, strip, undo, explicit save, preserve non-ANSI hex and plain files')
LUA
nvim --headless -u NONE -c "luafile $TMP/test.lua" -c 'qa!' >"$TMP/out.log" 2>&1 || { cat "$TMP/out.log"; exit 1; }
grep -F 'PASS: auto conceal ANSI SGR' "$TMP/out.log" || { cat "$TMP/out.log"; exit 1; }
