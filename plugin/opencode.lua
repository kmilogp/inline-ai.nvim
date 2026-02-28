local opencode = require('opencode')
local PROMPT_USAGE = 'Usage: OpencodePrompt [profile] <prompt>'

local function parse_prompt_args(raw)
  local args = vim.trim(raw or '')
  if args == '' then
    return nil, nil, PROMPT_USAGE
  end

  local first, rest = args:match('^(%S+)%s*(.*)$')
  if first and opencode.config.profiles[first] then
    local prompt = vim.trim(rest or '')
    if prompt == '' then
      return nil, nil, PROMPT_USAGE
    end
    return first, prompt, nil
  end

  return nil, args, nil
end

local function get_selection_from_range(opts)
  if not opts or not opts.range or opts.range == 0 then
    return nil
  end

  local start_line = opts.line1
  local end_line = opts.line2
  if type(start_line) ~= 'number' or type(end_line) ~= 'number' then
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  return {
    start_line = start_line,
    end_line = end_line,
    text = table.concat(lines, '\n'),
  }
end

local function prefill_prompt(profile)
  local profile_name = profile or (opencode.config.default_profile or 'fast')
  vim.api.nvim_input(':OpencodePrompt ' .. profile_name .. ' ')
end

vim.api.nvim_create_user_command('OpencodePrompt', function(opts)
  local profile, prompt, err = parse_prompt_args(opts.args)
  if err then
    vim.notify(err, vim.log.levels.WARN, { title = 'Opencode' })
    return
  end

  opencode.run_prompt(prompt, profile, {
    selection = get_selection_from_range(opts),
  })
end, {
  desc = 'Send AI prompt from command line',
  nargs = '+',
  range = true,
  complete = function(_, cmdline)
    local tokens = vim.split(cmdline, '%s+', { trimempty = true })
    if #tokens <= 2 then
      return vim.tbl_keys(opencode.config.profiles)
    end
    return {}
  end,
})

vim.keymap.set({ 'n', 'x' }, '<leader>of', function()
  prefill_prompt('fast')
end, { desc = 'Prefill fast AI prompt command' })

vim.keymap.set({ 'n', 'x' }, '<leader>od', function()
  prefill_prompt('deep')
end, { desc = 'Prefill deep AI prompt command' })

vim.keymap.set({ 'n', 'x' }, '<leader>op', function()
  prefill_prompt(nil)
end, { desc = 'Prefill default AI prompt command' })
