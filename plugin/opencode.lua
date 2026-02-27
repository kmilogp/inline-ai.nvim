local opencode = require('opencode')

vim.api.nvim_create_user_command('OpencodePrompt', function(opts)
  local profile = opts.args ~= '' and opts.args or nil
  opencode.open_prompt(profile, function(prompt, model, name, provider)
    opencode.send_prompt(prompt, model, name, provider)
  end)
end, {
  desc = 'Open floating input to send an AI CLI prompt',
  nargs = '?',
  complete = function()
    return vim.tbl_keys(opencode.config.profiles)
  end,
})

vim.keymap.set('n', '<leader>o', function()
  opencode.open_prompt('fast', function(prompt, model, name, provider)
    opencode.send_prompt(prompt, model, name, provider)
  end)
end, { desc = 'Open fast AI profile prompt' })

vim.keymap.set('n', '<leader>O', function()
  opencode.open_prompt('deep', function(prompt, model, name, provider)
    opencode.send_prompt(prompt, model, name, provider)
  end)
end, { desc = 'Open deep AI profile prompt' })
