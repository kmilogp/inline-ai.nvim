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

vim.api.nvim_create_user_command('OpencodePrompt', function(opts)
  local profile, prompt, err = parse_prompt_args(opts.args)
  if err then
    vim.notify(err, vim.log.levels.WARN, { title = 'Opencode' })
    return
  end

  opencode.run_prompt(prompt, profile)
end, {
  desc = 'Send AI prompt from command line',
  nargs = '+',
  complete = function(_, cmdline)
    local tokens = vim.split(cmdline, '%s+', { trimempty = true })
    if #tokens <= 2 then
      return vim.tbl_keys(opencode.config.profiles)
    end
    return {}
  end,
})

vim.keymap.set('n', '<leader>o', function()
  vim.api.nvim_input(':OpencodePrompt fast ')
end, { desc = 'Prefill fast AI prompt command' })

vim.keymap.set('n', '<leader>O', function()
  vim.api.nvim_input(':OpencodePrompt deep ')
end, { desc = 'Prefill deep AI prompt command' })
