local M = {}

local function create_prompt_window()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'prompt'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false

  local win_width = vim.api.nvim_win_get_width(0)
  local width = math.min(80, math.max(40, win_width - 4))

  local row = -1
  if vim.fn.line('.') <= 1 then
    row = 0
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'cursor',
    row = row,
    col = 0,
    width = width,
    height = 1,
    style = 'minimal',
    border = 'rounded',
  })

  return buf, win
end

function M.open(opts)
  local profile_name = opts.profile_name
  local cb = opts.cb
  if type(profile_name) == 'function' and cb == nil then
    cb = profile_name
    profile_name = nil
  end

  if type(cb) ~= 'function' then
    error('opencode.open_prompt expects a callback function')
  end

  local name, profile, provider, err = opts.resolve_profile(profile_name)
  if err then
    vim.notify(err, vim.log.levels.ERROR, { title = 'Opencode' })
    return
  end

  local include_full_file = profile.include_full_file_context ~= false
  local ctx = opts.get_context(include_full_file)
  local buf, win = create_prompt_window()

  local function close_prompt()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  vim.fn.prompt_setprompt(buf, 'Agent (' .. name .. '): ')
  vim.keymap.set('i', '<C-c>', close_prompt, { buffer = buf, silent = true })
  vim.keymap.set('n', '<Esc>', close_prompt, { buffer = buf, silent = true })

  vim.fn.prompt_setcallback(buf, function(input)
    local prompt_ctx = vim.tbl_extend('force', ctx, {
      input = input or '',
      auto_apply = profile.auto_apply == true or provider.auto_apply == true,
      provider_transport = provider.transport,
    })

    local prompt = opts.build_prompt(prompt_ctx, name)
    cb(prompt, profile.model, name, profile.provider, ctx)
    close_prompt()
  end)

  vim.fn.prompt_setinterrupt(buf, function()
    close_prompt()
  end)

  vim.cmd('startinsert')
end

return M
