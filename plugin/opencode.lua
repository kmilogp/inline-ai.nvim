-- Load the opencode module, which exposes prompt helpers and configuration.
local opencode = require 'opencode'

-- Expose a user command that accepts an optional variant name before opening a prompt.
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

-- Bind the simple prompt variant to <leader>o for quick access.
vim.keymap.set('n', '<leader>o', function()
  opencode.open_prompt('simple', function(prompt, model, name)
    opencode.send_prompt(prompt, model, name)
  end)
end, { desc = 'Open Opencode simple prompt' })

-- Bind the more feature-rich complex variant to <leader>O for power users.
vim.keymap.set('n', '<leader>O', function()
  opencode.open_prompt('complex', function(prompt, model, name)
    opencode.send_prompt(prompt, model, name)
  end)
end, { desc = 'Open Opencode complex prompt' })
