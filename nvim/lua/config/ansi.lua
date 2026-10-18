-- Hack-Jitsu ANSI log helpers. No external Neovim dependencies.
-- Conceals ONLY ANSI SGR color sequences; preserves the original bytes.
-- Never silently mutates/rewrites log files (important for pentest evidence).
local M = {}
local csi = '[0-9;:]*m'
local substitutions = {
  '\27%[' .. csi,           -- actual ESC [ 31m
  '\\x1[bB]%[' .. csi,      -- text "\\x1b[31m" (e.g. serialized logs)
  '\\u001[bB]%[' .. csi,    -- text "\\u001b[31m"
}
local vim_patterns = {
  [[\%x1b\[[0-9;:]*m]],
  [[\\x1[bB]\[[0-9;:]*m]],
  [[\\u001[bB]\[[0-9;:]*m]],
}

local function contains_color(line)
  for _, pattern in ipairs(substitutions) do
    if line:find(pattern) then return true end
  end
  return false
end

local function has_ansi_color(bufnr)
  local count = vim.api.nvim_buf_line_count(bufnr)
  local function scan(first, last)
    for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, first, last, false)) do
      if contains_color(line) then return true end
    end
    return false
  end
  return scan(0, math.min(count, 1000))
    or (count > 1000 and scan(math.max(1000, count - 200), count))
end

local function remove_matches()
  local previous = vim.w.hj_ansi_matches
  if not previous then return end
  for _, id in ipairs(previous) do
    pcall(vim.fn.matchdelete, id)
  end
  vim.w.hj_ansi_matches = nil
  -- Conceal options belong to a window, not a buffer. Restore the user's
  -- settings when the file is closed/toggled, including in LazyVim splits.
  if vim.w.hj_ansi_previous_level ~= nil then
    vim.wo.conceallevel = vim.w.hj_ansi_previous_level
    vim.wo.concealcursor = vim.w.hj_ansi_previous_cursor or ''
  end
  vim.w.hj_ansi_previous_level = nil
  vim.w.hj_ansi_previous_cursor = nil
end

local function conceal_current_window()
  local bufnr = vim.api.nvim_get_current_buf()
  remove_matches()
  if vim.bo[bufnr].buftype ~= '' then return end

  if vim.b[bufnr].hj_ansi_conceal == nil then
    vim.b[bufnr].hj_ansi_conceal = has_ansi_color(bufnr)
  end
  if not vim.b[bufnr].hj_ansi_conceal then
    return
  end

  vim.w.hj_ansi_previous_level = vim.wo.conceallevel
  vim.w.hj_ansi_previous_cursor = vim.wo.concealcursor
  vim.wo.conceallevel = 3
  vim.wo.concealcursor = 'nvic'
  local ids = {}
  for _, pattern in ipairs(vim_patterns) do
    local ok, id = pcall(vim.fn.matchadd, 'Conceal', pattern, 12, -1, { conceal = '' })
    if ok then table.insert(ids, id) end
  end
  vim.w.hj_ansi_matches = ids
end

local function strip_color()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype ~= '' or not vim.bo[bufnr].modifiable then
    vim.notify('HJAnsiStrip: buffer cannot be modified', vim.log.levels.ERROR)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local count, changed = 0, false
  for i, line in ipairs(lines) do
    local clean = line
    for _, pattern in ipairs(substitutions) do
      local n
      clean, n = clean:gsub(pattern, '')
      count = count + n
    end
    if clean ~= line then
      changed = true
      lines[i] = clean
    end
  end
  if changed then
    -- One undoable buffer edit. The disk is unchanged until explicit :w.
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.b[bufnr].hj_ansi_conceal = false
    conceal_current_window()
  end
  vim.notify(('HJAnsiStrip: removed %d color codes in memory; use :w to save or u to undo'):format(count))
end

function M.setup()
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWinEnter' }, {
    group = vim.api.nvim_create_augroup('HackJitsuAnsiView', { clear = true }),
    callback = function(ctx)
      if vim.api.nvim_get_current_buf() == ctx.buf then
        conceal_current_window()
      end
    end,
  })

  vim.api.nvim_create_user_command('HJAnsiToggle', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local active = vim.b[bufnr].hj_ansi_conceal
    if active == nil then active = has_ansi_color(bufnr) end
    vim.b[bufnr].hj_ansi_conceal = not active
    conceal_current_window()
    vim.notify('ANSI color codes ' .. (vim.b[bufnr].hj_ansi_conceal and 'hidden' or 'visible'))
  end, { desc = 'Toggle display of embedded ANSI color codes (no file modification)' })

  vim.api.nvim_create_user_command('HJAnsiStrip', strip_color, {
    desc = 'Remove only ANSI SGR color codes from current buffer (save with :w)',
  })
end

return M
