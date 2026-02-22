local opencode = require 'opencode'

vim.api.nvim_create_user_command('OpencodePrompt', function(opts)
  local variant = opts.args ~= '' and opts.args or nil
  opencode.open_prompt(variant, function(prompt, model, name)
    opencode.send_prompt(prompt, model, name)
  end)
end, {
  desc = 'Open floating input to send Opencode prompt',
  nargs = '?',
  complete = function() return vim.tbl_keys(opencode.config.variants) end,
})

vim.keymap.set('n', '<leader>o', function()
  opencode.open_prompt('simple', function(prompt, model, name)
    opencode.send_prompt(prompt, model, name)
  end)
end, { desc = 'Open Opencode simple prompt' })

vim.keymap.set('n', '<leader>O', function()
  opencode.open_prompt('complex', function(prompt, model, name)
    opencode.send_prompt(prompt, model, name)
  end)
end, { desc = 'Open Opencode complex prompt' })
