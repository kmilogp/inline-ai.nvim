package.path = table.concat({
  './lua/?.lua',
  './lua/?/init.lua',
  './tests/lua/?.lua',
  package.path,
}, ';')

local function deep_equal(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= 'table' then
    return a == b
  end

  for k, v in pairs(a) do
    if not deep_equal(v, b[k]) then
      return false
    end
  end
  for k, v in pairs(b) do
    if not deep_equal(v, a[k]) then
      return false
    end
  end
  return true
end

local function assert_true(value, message)
  if not value then
    error(message or 'expected true')
  end
end

local function assert_eq(actual, expected, message)
  if not deep_equal(actual, expected) then
    error((message or 'assert_eq failed') .. '\nexpected: ' .. vim.inspect(expected) .. '\nactual: ' .. vim.inspect(actual))
  end
end

local function assert_match(text, pattern, message)
  if type(text) ~= 'string' or not text:match(pattern) then
    error(message or ('expected ' .. tostring(text) .. ' to match ' .. tostring(pattern)))
  end
end

local function split_lines(value)
  local out = {}
  if value == '' then
    return { '' }
  end
  for line in (value .. '\n'):gmatch('(.-)\n') do
    table.insert(out, line)
  end
  return out
end

local function copy_lines(lines)
  local out = {}
  for i, line in ipairs(lines or {}) do
    out[i] = line
  end
  return out
end

local function attach_buffer_lines(vim_mock, initial_lines)
  local lines = copy_lines(initial_lines)

  vim_mock.api.nvim_buf_line_count = function()
    return #lines
  end

  vim_mock.api.nvim_buf_get_lines = function(_, start_idx, end_idx)
    local out = {}
    local last = end_idx
    if end_idx < 0 then
      last = #lines
    end
    for i = start_idx + 1, last do
      table.insert(out, lines[i])
    end
    return out
  end

  vim_mock.api.nvim_buf_set_lines = function(_, _, _, _, new_lines)
    lines = copy_lines(new_lines)
  end

  return function()
    return copy_lines(lines)
  end
end

local function make_vim_mock()
  local mock = {
    NIL = {},
    fn = {},
    api = {},
    bo = setmetatable({}, {
      __index = function(t, k)
        local value = {}
        rawset(t, k, value)
        return value
      end,
    }),
    keymap = { set = function() end },
    log = { levels = { INFO = 1, WARN = 2, ERROR = 3 } },
    notify = function() end,
    schedule = function(fn)
      fn()
    end,
    in_fast_event = function()
      return false
    end,
    tbl_extend = function(_, a, b)
      local out = {}
      for k, v in pairs(a or {}) do
        out[k] = v
      end
      for k, v in pairs(b or {}) do
        out[k] = v
      end
      return out
    end,
    split = function(value)
      return split_lines(value or '')
    end,
    inspect = function(value)
      if type(value) ~= 'table' then
        return tostring(value)
      end
      local parts = {}
      for k, v in pairs(value) do
        table.insert(parts, tostring(k) .. '=' .. tostring(v))
      end
      return '{' .. table.concat(parts, ',') .. '}'
    end,
    cmd = function() end,
  }

  mock.fn.json_encode = function()
    return '{}'
  end
  mock.fn.writefile = function() end
  mock.fn.getenv = function()
    return mock.NIL
  end
  mock.fn.expand = function()
    return ''
  end
  mock.fn.fnamemodify = function(value)
    return value
  end
  mock.fn.line = function()
    return 1
  end
  mock.fn.prompt_setprompt = function() end
  mock.fn.prompt_setcallback = function() end
  mock.fn.prompt_setinterrupt = function() end

  mock.api.nvim_get_current_buf = function()
    return 1
  end
  mock.api.nvim_win_get_cursor = function()
    return { 1, 0 }
  end
  mock.api.nvim_buf_get_lines = function()
    return {}
  end
  mock.api.nvim_buf_is_valid = function()
    return true
  end
  mock.api.nvim_buf_line_count = function()
    return 0
  end
  mock.api.nvim_buf_set_lines = function() end
  mock.api.nvim_create_buf = function()
    return 1
  end
  mock.api.nvim_win_get_width = function()
    return 100
  end
  mock.api.nvim_open_win = function()
    return 2
  end
  mock.api.nvim_win_is_valid = function()
    return true
  end
  mock.api.nvim_win_close = function() end
  mock.api.nvim_buf_delete = function() end

  return mock
end

local function with_vim(mock, fn)
  local old_vim = _G.vim
  _G.vim = mock
  local ok, err = pcall(fn)
  _G.vim = old_vim
  if not ok then
    error(err)
  end
end

local function reload(name)
  package.loaded[name] = nil
  return require(name)
end

local tests = {}

tests['defaults.build uses xdg path'] = function()
  local vim_mock = make_vim_mock()
  vim_mock.fn.getenv = function()
    return '/tmp/xdg'
  end
  with_vim(vim_mock, function()
    local defaults = reload('inline_ai.defaults')
    local config = defaults.build({ fast = function() end, deep = function() end }, {
      default_providers = function()
        return { ollama = true }
      end,
    })
    assert_eq(config.default_profile, 'fast')
    assert_eq(config.debug_log_file, '/tmp/xdg/inline-ai/inline-ai.nvim.log')
    assert_true(type(config.profiles.fast.template) == 'function')
  end)
end

tests['logging start/end writes edit event'] = function()
  local vim_mock = make_vim_mock()
  local writes = {}
  local encoded = {}
  local hr = { 1000000000, 4000000000 }
  vim_mock.uv = {
    hrtime = function()
      local value = hr[1]
      table.remove(hr, 1)
      return value
    end,
  }
  vim_mock.fn.json_encode = function(value)
    table.insert(encoded, value)
    return 'json'
  end
  vim_mock.fn.writefile = function(lines, path, mode)
    table.insert(writes, { lines = lines, path = path, mode = mode })
  end
  with_vim(vim_mock, function()
    local logging = reload('inline_ai.logging')
    local state = { config = { debug_log_file = '/tmp/log' } }
    logging.start_edit(state, 'fast', 'ollama', 'qwen', 'abc', { file = 'a.lua', line = 1, col = 2 })
    logging.end_edit(state, 'ok', { apply_mode = 'auto' })
    assert_eq(#writes, 1)
    assert_eq(writes[1].path, '/tmp/log')
    assert_eq(writes[1].mode, 'a')
    assert_eq(encoded[1].event, 'edit')
    assert_eq(encoded[1].status, 'ok')
    assert_eq(encoded[1].duration_ms, 3000)
    assert_eq(state.last_edit_session, nil)
  end)
end

tests['logging schedules in fast event'] = function()
  local vim_mock = make_vim_mock()
  local scheduled = 0
  local writes = 0
  vim_mock.in_fast_event = function()
    return true
  end
  vim_mock.schedule = function(fn)
    scheduled = scheduled + 1
    fn()
  end
  vim_mock.fn.writefile = function()
    writes = writes + 1
  end
  with_vim(vim_mock, function()
    local logging = reload('inline_ai.logging')
    local state = { config = { debug_log_file = '/tmp/log' } }
    logging.log_ollama_response(state, 'abc', {})
    assert_eq(scheduled, 1)
    assert_eq(writes, 1)
  end)
end

tests['context.get returns cursor and file context'] = function()
  local vim_mock = make_vim_mock()
  vim_mock.api.nvim_get_current_buf = function()
    return 7
  end
  vim_mock.api.nvim_win_get_cursor = function()
    return { 12, 3 }
  end
  vim_mock.api.nvim_buf_get_lines = function(_, start_idx, end_idx)
    if start_idx == 11 and end_idx == 12 then
      return { 'target line' }
    end
    return {}
  end
  vim_mock.bo[7] = { filetype = 'lua' }
  vim_mock.fn.expand = function()
    return '/abs/path/file.lua'
  end
  vim_mock.fn.fnamemodify = function()
    return 'file.lua'
  end
  with_vim(vim_mock, function()
    local context = reload('inline_ai.context')
    local called_include = nil
    local result = context.get({
      build_file_context = function(_, _, include)
        called_include = include
        return {
          total_lines = 100,
          snippet_start = 1,
          snippet_end = 20,
          snippet_text = 'snippet',
          full_file_text = 'full',
          has_full_file_context = true,
        }
      end,
    }, false, {
      selection = {
        start_line = 9,
        end_line = 12,
        text = 'selected lines',
      },
    })

    assert_eq(called_include, false)
    assert_eq(result.bufnr, 7)
    assert_eq(result.line, 12)
    assert_eq(result.col, 4)
    assert_eq(result.file, 'file.lua')
    assert_eq(result.filetype, 'lua')
    assert_eq(result.line_text, 'target line')
    assert_eq(result.selected_text, 'selected lines')
    assert_eq(result.selection_start_line, 9)
    assert_eq(result.selection_end_line, 12)
  end)
end

tests['profiles.resolve and build_prompt'] = function()
  local vim_mock = make_vim_mock()
  with_vim(vim_mock, function()
    local profiles = reload('inline_ai.profiles')
    local config = {
      default_profile = 'fast',
      profiles = {
        fast = {
          provider = 'ollama',
          template = function(ctx)
            return 'Task: ' .. ctx.input
          end,
        },
      },
    }

    local name, profile, provider, err = profiles.resolve(config, nil, {
      resolve_provider = function(_, provider_name)
        return { name = provider_name }, nil
      end,
    })
    assert_eq(err, nil)
    assert_eq(name, 'fast')
    assert_eq(profile.provider, 'ollama')
    assert_eq(provider.name, 'ollama')

    local prompt = profiles.build_prompt(config, 'fast', { input = 'x' }, {
      resolve_provider = function()
        return {}, nil
      end,
    })
    assert_eq(prompt, 'Task: x')
  end)
end

tests['templates.fast includes selected text context'] = function()
  local vim_mock = make_vim_mock()
  with_vim(vim_mock, function()
    local templates = reload('inline_ai.templates')
    local prompt = templates.fast({
      input = 'Refactor selection',
      file = 'x.lua',
      line = 3,
      col = 1,
      filetype = 'lua',
      line_text = 'local x = 1',
      total_lines = 10,
      snippet_start = 1,
      snippet_end = 5,
      snippet_text = '1: local x = 1',
      has_full_file_context = false,
      selected_text = 'x = x + 1',
      selection_start_line = 3,
      selection_end_line = 3,
    })
    assert_match(prompt, 'Selected text %(%d+%-%d+%)')
    assert_match(prompt, 'x = x %+ 1')
  end)
end

tests['templates.fast uses ollama edit-block contract'] = function()
  local vim_mock = make_vim_mock()
  with_vim(vim_mock, function()
    local templates = reload('inline_ai.templates')
    local prompt = templates.fast({
      input = 'Do it',
      provider_transport = 'ollama_http',
      file = 'x.lua',
      line = 1,
      col = 1,
      filetype = 'lua',
      line_text = 'x',
      total_lines = 1,
      snippet_start = 1,
      snippet_end = 1,
      snippet_text = '1: x',
      has_full_file_context = false,
    })
    assert_match(prompt, 'BEGIN_REPLACE')
    assert_match(prompt, 'Return only edit blocks, nothing else')
  end)
end

tests['templates.fast uses tool-edit contract for cli providers'] = function()
  local vim_mock = make_vim_mock()
  with_vim(vim_mock, function()
    local templates = reload('inline_ai.templates')
    local prompt = templates.fast({
      input = 'Do it',
      provider_transport = 'cli',
      file = 'x.lua',
      line = 1,
      col = 1,
      filetype = 'lua',
      line_text = 'x',
      total_lines = 1,
      snippet_start = 1,
      snippet_end = 1,
      snippet_text = '1: x',
      has_full_file_context = false,
    })
    assert_match(prompt, 'apply the edit directly')
    assert_match(prompt, 'LINE <number>: <new content>')
  end)
end

tests['edit_blocks.parse replace and insert'] = function()
  local vim_mock = make_vim_mock()
  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local blocks, err = edit_blocks.parse(table.concat({
      'BEGIN_REPLACE',
      'OLD:',
      'a',
      'NEW:',
      'b',
      'END_REPLACE',
      '',
      'BEGIN_INSERT',
      'AFTER:',
      'b',
      'NEW:',
      'c',
      'END_INSERT',
    }, '\n'))
    assert_eq(err, nil)
    assert_eq(#blocks, 2)
    assert_eq(blocks[1].kind, 'replace')
    assert_eq(blocks[2].kind, 'insert')
    assert_eq(blocks[2].position, 'after')
  end)
end

tests['edit_blocks.parse tolerates trailing spaces in control lines'] = function()
  local vim_mock = make_vim_mock()
  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local blocks, err = edit_blocks.parse(table.concat({
      'BEGIN_REPLACE  ',
      'OLD:  ',
      "pcall(require('telescope').load_extension, 'live_grep_args')  ",
      'NEW:  ',
      "-- pcall(require('telescope').load_extension, 'live_grep_args')  ",
      'END_REPLACE  ',
    }, '\n'))
    assert_eq(err, nil)
    assert_eq(#blocks, 1)
    assert_eq(blocks[1].kind, 'replace')
    assert_eq(blocks[1].anchor_lines, { "pcall(require('telescope').load_extension, 'live_grep_args')  " })
  end)
end

tests['edit_blocks.apply ai response on telescope snippet'] = function()
  local vim_mock = make_vim_mock()
  local get_lines = attach_buffer_lines(vim_mock, {
    "pcall(require('telescope').load_extension, 'live_grep_args')",
    '',
    "local extensions = require('telescope').extensions",
    '',
    "vim.keymap.set('n', '<leader>sg', extensions.live_grep_args.live_grep_args, { desc = '[S]earch by [G]rep' })",
  })
  vim_mock.bo[1] = { modifiable = true }

  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local response_text = table.concat({
      'BEGIN_REPLACE  ',
      'OLD:  ',
      "pcall(require('telescope').load_extension, 'live_grep_args')  ",
      'NEW:  ',
      "-- pcall(require('telescope').load_extension, 'live_grep_args')  ",
      'END_REPLACE',
    }, '\n')

    local blocks, err = edit_blocks.parse(response_text)
    assert_eq(err, nil)
    local ok, msg, applied = edit_blocks.apply({ bufnr = 1 }, blocks)
    assert_true(ok)
    assert_eq(applied, 1)
    assert_match(msg, 'Applied 1')

    assert_eq(get_lines(), {
      "-- pcall(require('telescope').load_extension, 'live_grep_args')  ",
      '',
      "local extensions = require('telescope').extensions",
      '',
      "vim.keymap.set('n', '<leader>sg', extensions.live_grep_args.live_grep_args, { desc = '[S]earch by [G]rep' })",
    })
  end)
end

tests['edit_blocks.parse strips numbered lines in old and new'] = function()
  local vim_mock = make_vim_mock()
  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local blocks, err = edit_blocks.parse(table.concat({
      'BEGIN_REPLACE',
      'OLD:',
      '1: alpha',
      '2: beta',
      'NEW:',
      '1: gamma',
      'END_REPLACE',
    }, '\n'))
    assert_eq(err, nil)
    assert_eq(blocks[1].anchor_lines, { 'alpha', 'beta' })
    assert_eq(blocks[1].new_lines, { 'gamma' })
  end)
end

tests['edit_blocks.parse trims trailing blank anchor lines'] = function()
  local vim_mock = make_vim_mock()
  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local blocks, err = edit_blocks.parse(table.concat({
      'BEGIN_REPLACE',
      'OLD:',
      'a',
      '',
      'NEW:',
      'b',
      '',
      'END_REPLACE',
    }, '\n'))
    assert_eq(err, nil)
    assert_eq(blocks[1].anchor_lines, { 'a' })
    assert_eq(blocks[1].new_lines, { 'b' })
  end)
end

tests['edit_blocks.parse allows blank insert anchor lines'] = function()
  local vim_mock = make_vim_mock()
  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local blocks, err = edit_blocks.parse(table.concat({
      'BEGIN_INSERT',
      'BEFORE:',
      '3: ',
      'NEW:',
      'function my_empty_function()',
      'end',
      'END_INSERT',
    }, '\n'))
    assert_eq(err, nil)
    assert_eq(#blocks, 1)
    assert_eq(blocks[1].kind, 'insert')
    assert_eq(blocks[1].position, 'before')
    assert_eq(blocks[1].anchor_lines, { '' })
  end)
end

tests['edit_blocks.apply replace insert and skip'] = function()
  local vim_mock = make_vim_mock()
  local get_lines = attach_buffer_lines(vim_mock, { 'A', 'B', 'C' })
  vim_mock.bo[1] = { modifiable = true }

  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local ok, msg, applied = edit_blocks.apply({ bufnr = 1 }, {
      { kind = 'replace', anchor_lines = { 'A' }, new_lines = { 'X' } },
      { kind = 'replace', anchor_lines = { 'A' }, new_lines = { 'X' } },
      { kind = 'insert', position = 'after', anchor_lines = { 'X' }, new_lines = { 'Y' } },
    })
    assert_true(ok)
    assert_eq(applied, 2)
    assert_match(msg, 'skipped 1')
    assert_eq(get_lines(), { 'X', 'Y', 'B', 'C' })
  end)
end

tests['edit_blocks.apply ambiguous anchor fails'] = function()
  local vim_mock = make_vim_mock()
  attach_buffer_lines(vim_mock, { 'A', 'A' })
  vim_mock.bo[1] = { modifiable = true }
  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local ok, msg = edit_blocks.apply({ bufnr = 1 }, {
      { kind = 'replace', anchor_lines = { 'A' }, new_lines = { 'Z' } },
    })
    assert_eq(ok, false)
    assert_match(msg, 'ambiguous')
  end)
end

tests['edit_blocks.apply inserts before unique blank line'] = function()
  local vim_mock = make_vim_mock()
  local get_lines = attach_buffer_lines(vim_mock, { 'alpha', '', 'omega' })
  vim_mock.bo[1] = { modifiable = true }

  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local ok, msg = edit_blocks.apply({ bufnr = 1 }, {
      {
        kind = 'insert',
        position = 'before',
        anchor_lines = { '' },
        new_lines = { 'function my_empty_function()', 'end' },
      },
    })
    assert_true(ok)
    assert_match(msg, 'Applied 1')
    assert_eq(get_lines(), {
      'alpha',
      'function my_empty_function()',
      'end',
      '',
      'omega',
    })
  end)
end

tests['edit_blocks.apply matches numbered anchors'] = function()
  local vim_mock = make_vim_mock()
  local get_lines = attach_buffer_lines(vim_mock, {
    '-- Load telescope extensions',
    'pcall(require("telescope"))',
  })
  vim_mock.bo[1] = { modifiable = true }

  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local ok, msg = edit_blocks.apply({ bufnr = 1 }, {
      {
        kind = 'replace',
        anchor_lines = { '1: -- Load telescope extensions' },
        new_lines = {},
      },
    })
    assert_true(ok)
    assert_match(msg, 'Applied 1')
    assert_eq(get_lines(), { 'pcall(require("telescope"))' })
  end)
end

tests['edit_blocks.apply reported numbered replace blocks'] = function()
  local vim_mock = make_vim_mock()
  local get_lines = attach_buffer_lines(vim_mock, {
    '-- Load telescope extensions',
    "pcall(require('telescope').load_extension, 'live_grep_args')",
    '-- Enable live_grep_args extension for advanced grep functionality',
    '',
    '-- Access telescope extensions module',
    '',
    '-- Set keymap for live grep args search',
    "vim.keymap.set('n', '<leader>sg', extensions.live_grep_args.live_grep_args, { desc = '[S]earch by [G]rep' })",
    '-- Search using live grep args with custom description',
  })
  vim_mock.bo[1] = { modifiable = true }

  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local blocks, err = edit_blocks.parse(table.concat({
      'BEGIN_REPLACE',
      'OLD:',
      '1: -- Load telescope extensions',
      "2: pcall(require('telescope').load_extension, 'live_grep_args')",
      '3: -- Enable live_grep_args extension for advanced grep functionality',
      'NEW:',
      "1: pcall(require('telescope').load_extension, 'live_grep_args')",
      'END_REPLACE',
      '',
      'BEGIN_REPLACE',
      'OLD:',
      '5: -- Access telescope extensions module',
      'NEW:',
      "5: local extensions = require('telescope').extensions",
      'END_REPLACE',
      '',
      'BEGIN_REPLACE',
      'OLD:',
      '8: -- Set keymap for live grep args search',
      "9: vim.keymap.set('n', '<leader>sg', extensions.live_grep_args.live_grep_args, { desc = '[S]earch by [G]rep' })",
      '10: -- Search using live grep args with custom description',
      'NEW:',
      "8: vim.keymap.set('n', '<leader>sg', extensions.live_grep_args.live_grep_args, { desc = '[S]earch by [G]rep' })",
      'END_REPLACE',
    }, '\n'))
    assert_eq(err, nil)

    local ok, msg = edit_blocks.apply({ bufnr = 1 }, blocks)
    assert_true(ok)
    assert_match(msg, 'Applied 3')
    assert_eq(get_lines(), {
      "pcall(require('telescope').load_extension, 'live_grep_args')",
      '',
      "local extensions = require('telescope').extensions",
      '',
      "vim.keymap.set('n', '<leader>sg', extensions.live_grep_args.live_grep_args, { desc = '[S]earch by [G]rep' })",
    })
  end)
end

tests['edit_blocks.apply does not skip when old-only lines still exist'] = function()
  local vim_mock = make_vim_mock()
  attach_buffer_lines(vim_mock, {
    'keep',
    '-- comment to remove',
    'target',
    '-- trailing comment',
  })
  vim_mock.bo[1] = { modifiable = true }

  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local ok, msg = edit_blocks.apply({ bufnr = 1 }, {
      {
        kind = 'replace',
        anchor_lines = { '-- comment to remove', 'target', '-- trailing comment', '' },
        new_lines = { 'target' },
      },
    })
    assert_eq(ok, false)
    assert_match(msg, 'anchor block not found')
  end)
end

tests['edit_blocks.apply handles old block with trailing blank at eof'] = function()
  local vim_mock = make_vim_mock()
  local get_lines = attach_buffer_lines(vim_mock, {
    "pcall(require('telescope').load_extension, 'live_grep_args')",
    "local extensions = require('telescope').extensions",
    '-- Set keymap for live grep args search',
    "vim.keymap.set('n', '<leader>sg', extensions.live_grep_args.live_grep_args, { desc = '[S]earch by [G]rep' })",
    '-- Search using live grep args with custom description',
  })
  vim_mock.bo[1] = { modifiable = true }

  with_vim(vim_mock, function()
    local edit_blocks = reload('inline_ai.edit_blocks')
    local blocks, err = edit_blocks.parse(table.concat({
      'BEGIN_REPLACE',
      'OLD:',
      '-- Set keymap for live grep args search',
      "vim.keymap.set('n', '<leader>sg', extensions.live_grep_args.live_grep_args, { desc = '[S]earch by [G]rep' })",
      '-- Search using live grep args with custom description',
      '',
      'NEW:',
      "vim.keymap.set('n', '<leader>sg', extensions.live_grep_args.live_grep_args, { desc = '[S]earch by [G]rep' })",
      'END_REPLACE',
    }, '\n'))
    assert_eq(err, nil)

    local ok, msg = edit_blocks.apply({ bufnr = 1 }, blocks)
    assert_true(ok)
    assert_match(msg, 'Applied 1')
    assert_eq(get_lines(), {
      "pcall(require('telescope').load_extension, 'live_grep_args')",
      "local extensions = require('telescope').extensions",
      "vim.keymap.set('n', '<leader>sg', extensions.live_grep_args.live_grep_args, { desc = '[S]earch by [G]rep' })",
    })
  end)
end

tests['sender handles resolve profile error'] = function()
  local vim_mock = make_vim_mock()
  local notified = {}
  vim_mock.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end
  with_vim(vim_mock, function()
    local sender = reload('inline_ai.sender')
    local end_calls = {}
    sender.send({ config = {} }, {
      providers = {},
      profiles = {
        resolve = function()
          return nil, nil, nil, 'bad profile'
        end,
      },
      logging = {
        end_edit = function(_, status, details)
          table.insert(end_calls, { status = status, details = details })
        end,
      },
      edit_blocks = {},
      transport_cli = {},
      transport_ollama = {},
    }, 'prompt', nil, 'fast', nil)
    assert_eq(end_calls[1].status, 'error')
    assert_eq(end_calls[1].details.phase, 'resolve_profile')
    assert_eq(notified[1].msg, 'bad profile')
  end)
end

tests['sender cli success reloads target buffer from disk'] = function()
  local vim_mock = make_vim_mock()
  local cmd_calls = {}
  local notified = {}
  vim_mock.cmd = function(command)
    table.insert(cmd_calls, command)
  end
  vim_mock.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end

  with_vim(vim_mock, function()
    local sender = reload('inline_ai.sender')
    local end_calls = {}
    sender.send({
      config = {},
      last_context = { bufnr = 1 },
    }, {
      providers = {},
      profiles = {
        resolve = function()
          return 'fast', { provider = 'codex', model = 'gpt' }, { transport = 'cli' }, nil
        end,
      },
      logging = {
        end_edit = function(_, status, details)
          table.insert(end_calls, { status = status, details = details })
        end,
        log_ollama_response = function() end,
      },
      edit_blocks = {},
      transport_cli = {
        send = function(_, _, _, _, cb)
          cb(true, { text = 'done' }, nil, { status = 'ok' })
        end,
      },
      transport_ollama = {
        send = function() end,
      },
    }, 'prompt', nil, 'fast', nil)

    assert_eq(cmd_calls[1], 'checktime 1')
    assert_eq(end_calls[1].status, 'ok')
    assert_eq(end_calls[1].details.apply_mode, 'provider_output')
    assert_eq(notified[1].msg, 'done')
  end)
end

tests['sender ollama edit-block apply success'] = function()
  local vim_mock = make_vim_mock()
  local notified = {}
  vim_mock.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end

  with_vim(vim_mock, function()
    local sender = reload('inline_ai.sender')
    local end_calls = {}
    local ollama_logged = 0
    sender.send({
      config = {},
      last_context = { bufnr = 1 },
    }, {
      providers = {},
      profiles = {
        resolve = function()
          return 'fast', { provider = 'ollama', model = 'qwen' }, { transport = 'ollama_http' }, nil
        end,
      },
      logging = {
        end_edit = function(_, status, details)
          table.insert(end_calls, { status = status, details = details })
        end,
        log_ollama_response = function()
          ollama_logged = ollama_logged + 1
        end,
      },
      edit_blocks = {
        parse = function()
          return { { kind = 'replace' }, { kind = 'insert' } }, nil
        end,
        apply = function()
          return true, 'Applied 2 edit block(s)', 2
        end,
      },
      transport_cli = {
        send = function() end,
      },
      transport_ollama = {
        send = function(_, _, _, _, cb)
          cb(true, { text = 'ops' }, nil, { status = 'ok' })
        end,
      },
    }, 'prompt', nil, 'fast', nil)

    assert_eq(ollama_logged, 1)
    assert_eq(end_calls[1].status, 'ok')
    assert_eq(end_calls[1].details.apply_mode, 'auto')
    assert_eq(end_calls[1].details.applied_block_count, 2)
    assert_match(notified[1].msg, 'Applied 2')
  end)
end

local failures = {}
local total = 0
for name, fn in pairs(tests) do
  total = total + 1
  local ok, err = pcall(fn)
  if ok then
    print('ok - ' .. name)
  else
    table.insert(failures, { name = name, err = err })
    print('not ok - ' .. name)
    print('  ' .. tostring(err))
  end
end

print(string.format('\n%d tests, %d failures', total, #failures))
if #failures > 0 then
  os.exit(1)
end
