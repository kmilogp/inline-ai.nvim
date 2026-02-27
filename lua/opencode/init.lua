local M = {}

local providers = require('opencode.providers')
local transport_cli = require('opencode.transport_cli')

M.last_prompt = nil
M.last_model = nil
M.last_profile = nil
M.last_provider = nil

local function opencode_data_path()
  local data_home = vim.fn.getenv('XDG_DATA_HOME')
  if data_home == vim.NIL or data_home == '' then
    data_home = vim.fn.expand('~/.local/share')
  end
  return data_home .. '/opencode'
end

local function fast_template(ctx)
  return table.concat({
    'Task: ' .. (ctx.input or ''),
    'Apply the change directly. Do not ask for confirmation.',
    'Use tools as needed to read and edit files.',
    '',
    'Context:',
    '- file: ' .. (ctx.file or ''),
    '- line: ' .. tostring(ctx.line or ''),
  }, '\n')
end

local function deep_template(ctx)
  return table.concat({
    'Task: ' .. (ctx.input or ''),
    '',
    'Context:',
    '- file: ' .. (ctx.file or ''),
    '- line: ' .. tostring(ctx.line or ''),
    '- col: ' .. tostring(ctx.col or ''),
    '- filetype: ' .. (ctx.filetype or ''),
    '- line_text: ' .. (ctx.line_text or ''),
  }, '\n')
end

M.config = {
  default_profile = 'fast',
  debug_log_file = opencode_data_path() .. '/opencode.nvim.log',
  providers = providers.default_providers(),
  profiles = {
    fast = {
      provider = 'opencode',
      model = 'openai/gpt-5.1-codex-mini',
      template = fast_template,
    },
    deep = {
      provider = 'opencode',
      model = 'openai/gpt-5.2-codex',
      template = deep_template,
    },
    simple = {
      provider = 'opencode',
      model = 'openai/gpt-5.1-codex-mini',
      template = fast_template,
    },
    complex = {
      provider = 'opencode',
      model = 'openai/gpt-5.2-codex',
      template = deep_template,
    },
  },
}

function M.setup(opts)
  if type(opts) ~= 'table' then
    return
  end
  M.config = vim.tbl_deep_extend('force', M.config, opts)
end

local function get_line_text(bufnr, line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)
  return lines[1] or ''
end

function M.get_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local file = vim.fn.expand('%:p')
  if file == '' then
    file = '[No Name]'
  else
    file = vim.fn.fnamemodify(file, ':.')
  end

  return {
    bufnr = bufnr,
    line = cursor[1],
    col = cursor[2] + 1,
    file = file,
    filetype = vim.bo[bufnr].filetype,
    line_text = get_line_text(bufnr, cursor[1]),
  }
end

local function resolve_profile(profile_name)
  local name = profile_name or M.config.default_profile
  local profile = M.config.profiles[name]
  if not profile then
    return nil, nil, nil, 'Unknown profile: ' .. tostring(name)
  end

  local provider_name = profile.provider
  if not provider_name or provider_name == '' then
    return nil, nil, nil, 'Profile "' .. tostring(name) .. '" has no provider configured'
  end

  local provider, provider_err = providers.resolve_provider(M.config, provider_name)
  if not provider then
    return nil, nil, nil, provider_err
  end

  return name, profile, provider, nil
end

function M.build_prompt(ctx, profile_name)
  local name, profile, _, err = resolve_profile(profile_name)
  if err then
    error('opencode.build_prompt ' .. err)
  end

  if type(profile.template) ~= 'function' then
    error('opencode.build_prompt profile has no template function: ' .. tostring(name))
  end

  return profile.template(ctx)
end

local function resolve_transport()
  return transport_cli
end

function M.send_prompt(prompt, model, profile_name, provider_name)
  local name, profile, provider, err = resolve_profile(profile_name)
  if err then
    vim.notify(err, vim.log.levels.ERROR, { title = 'Opencode' })
    return
  end

  if provider_name and provider_name ~= '' and provider_name ~= profile.provider then
    vim.notify('Profile/provider mismatch: ' .. provider_name .. ' vs ' .. profile.provider, vim.log.levels.ERROR, { title = 'Opencode' })
    return
  end

  local resolved_model = model or profile.model
  local title = 'Opencode (' .. name .. ' / ' .. profile.provider .. ')'
  local transport = resolve_transport()

  transport.send(M, provider, prompt, resolved_model, function(ok, data, transport_err)
    if not ok then
      vim.notify(transport_err, vim.log.levels.ERROR, { title = title })
      return
    end

    local text = data.text or ''
    if text ~= '' then
      vim.notify(text, vim.log.levels.INFO, { title = title })
    end
  end)
end

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

function M.open_prompt(profile_name, cb)
  if type(profile_name) == 'function' and cb == nil then
    cb = profile_name
    profile_name = nil
  end

  if type(cb) ~= 'function' then
    error('opencode.open_prompt expects a callback function')
  end

  local name, profile, _, err = resolve_profile(profile_name)
  if err then
    vim.notify(err, vim.log.levels.ERROR, { title = 'Opencode' })
    return
  end

  local ctx = M.get_context()
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
    local prompt = M.build_prompt(vim.tbl_extend('force', ctx, { input = input or '' }), name)
    local model = profile.model

    M.last_prompt = prompt
    M.last_model = model
    M.last_profile = name
    M.last_provider = profile.provider

    cb(prompt, model, name, profile.provider)
    close_prompt()
  end)

  vim.fn.prompt_setinterrupt(buf, function()
    close_prompt()
  end)

  vim.cmd('startinsert')
end

return M
