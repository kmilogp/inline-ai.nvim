local inline_ai = require('inline_ai')
local predefined_prompts = require('inline_ai.predefined_prompts')
local PROMPT_USAGE = 'Usage: InlineAiPrompt [profile] <prompt>'

local function parse_prompt_args(raw)
  local args = vim.trim(raw or '')
  if args == '' then
    return nil, nil, PROMPT_USAGE
  end

  local first, rest = args:match('^(%S+)%s*(.*)$')
  if first and inline_ai.config.profiles[first] then
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
  local profile_name = profile or (inline_ai.config.default_profile or 'fast')
  vim.api.nvim_input(':InlineAiPrompt ' .. profile_name .. ' ')
end

local function run_predefined_prompt(item)
  inline_ai.run_prompt(item.prompt, item.profile)
end

local function open_predefined_prompt_picker()
  local prompts, prompts_err, path = predefined_prompts.load(inline_ai.config)
  if prompts_err then
    vim.notify(prompts_err, vim.log.levels.ERROR, { title = 'Inline AI' })
    return
  end

  local ok_pickers, pickers = pcall(require, 'telescope.pickers')
  if not ok_pickers then
    vim.notify('InlineAiPromptPicker requires telescope.nvim', vim.log.levels.ERROR, { title = 'Inline AI' })
    return
  end

  local finders = require('telescope.finders')
  local config_values = require('telescope.config').values
  local previewers = require('telescope.previewers')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  pickers.new({}, {
    prompt_title = 'Inline AI Prompts (' .. path .. ')',
    finder = finders.new_table({
      results = prompts,
      entry_maker = function(item)
        local first_line = (item.prompt or ''):match('([^\n]+)') or ''
        first_line = vim.trim(first_line)
        if #first_line > 80 then
          first_line = first_line:sub(1, 77) .. '...'
        end

        local display = item.title .. ' [' .. item.profile .. ']'
        if item.description ~= '' then
          display = display .. ' - ' .. item.description
        end
        if first_line ~= '' then
          display = display .. ' :: ' .. first_line
        end
        return {
          value = item,
          display = display,
          ordinal = table.concat({ item.title, item.profile, item.description, item.prompt }, ' '),
        }
      end,
    }),
    sorter = config_values.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      title = 'Prompt Content',
      define_preview = function(self, entry)
        local item = entry and entry.value or nil
        local lines = vim.split(item and item.prompt or '', '\n', { plain = true })
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end,
    }),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection and selection.value then
          run_predefined_prompt(selection.value)
        end
      end)
      return true
    end,
  }):find()
end

vim.api.nvim_create_user_command('InlineAiPrompt', function(opts)
  local profile, prompt, err = parse_prompt_args(opts.args)
  if err then
    vim.notify(err, vim.log.levels.WARN, { title = 'Inline AI' })
    return
  end

  inline_ai.run_prompt(prompt, profile, {
    selection = get_selection_from_range(opts),
  })
end, {
  desc = 'Send AI prompt from command line',
  nargs = '+',
  range = true,
  complete = function(_, cmdline)
    local tokens = vim.split(cmdline, '%s+', { trimempty = true })
    if #tokens <= 2 then
      return vim.tbl_keys(inline_ai.config.profiles)
    end
    return {}
  end,
})

vim.api.nvim_create_user_command('InlineAiPromptPicker', function()
  open_predefined_prompt_picker()
end, {
  desc = 'Pick and run a predefined AI prompt',
})

vim.keymap.set({ 'n', 'x' }, '<leader>of', function()
  prefill_prompt('fast')
end, { desc = 'Prefill fast AI prompt command' })

vim.keymap.set({ 'n', 'x' }, '<leader>od', function()
  prefill_prompt('deep')
end, { desc = 'Prefill deep AI prompt command' })

vim.keymap.set({ 'n', 'x' }, '<leader>op', function()
  open_predefined_prompt_picker()
end, { desc = 'Open predefined AI prompt picker' })
