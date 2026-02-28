local M = {}

local MAX_SNIPPET_RADIUS = 40

local function normalize_task(input)
  local value = tostring(input or '')
  value = value:gsub('^%s+', '')
  value = value:gsub('%s+$', '')
  if value == '' then
    return 'Apply a safe, minimal edit based on the provided context.'
  end
  return value
end

local function format_numbered_lines(lines, start_line)
  local out = {}
  for index, text in ipairs(lines) do
    out[index] = tostring(start_line + index - 1) .. ': ' .. text
  end
  return table.concat(out, '\n')
end

function M.build_file_context(bufnr, line, include_full_file)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local start_line = math.max(1, line - MAX_SNIPPET_RADIUS)
  local end_line = math.min(total_lines, line + MAX_SNIPPET_RADIUS)

  local snippet_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local snippet_text = format_numbered_lines(snippet_lines, start_line)

  local full_file_text = ''
  if include_full_file ~= false then
    local full_file_lines = vim.api.nvim_buf_get_lines(bufnr, 0, total_lines, false)
    full_file_text = table.concat(full_file_lines, '\n')
  end

  return {
    total_lines = total_lines,
    snippet_start = start_line,
    snippet_end = end_line,
    snippet_text = snippet_text,
    full_file_text = full_file_text,
    has_full_file_context = include_full_file ~= false,
  }
end

local function build_edit_contract(ctx)
  local file_label = (ctx.file and ctx.file ~= '') and ctx.file or '[No Name]'
  if ctx.auto_apply then
    return table.concat({
      'Output contract (auto-apply mode):',
      '- You cannot edit files directly. Return only edit blocks for ' .. file_label .. '.',
      '- Use one of these exact block formats:',
      '  BEGIN_REPLACE',
      '  OLD:',
      '  <exact current lines to replace>',
      '  NEW:',
      '  <replacement lines; empty means delete the block>',
      '  END_REPLACE',
      '  BEGIN_INSERT',
      '  BEFORE: or AFTER:',
      '  <exact anchor lines that already exist>',
      '  NEW:',
      '  <new lines to insert>',
      '  END_INSERT',
      '- You may return multiple blocks one after another.',
      '- OLD/anchor content must match existing file lines exactly and uniquely.',
      '- Blank-line anchors are allowed for insert blocks (a blank line between BEFORE:/AFTER: and NEW:).',
      '- If a blank-line anchor is ambiguous, include more surrounding anchor lines so it is unique.',
      '- Do not include numbered prefixes like "12: " in OLD/anchor lines.',
      '- Do not return full file content.',
      '- Do not wrap output in markdown fences.',
      '- Return only edit blocks, nothing else.',
    }, '\n')
  end

  return table.concat({
    'Output contract:',
    '- If your environment supports file tools, apply the edit directly to ' .. file_label .. ' and then report what changed.',
    '- If your environment does not support tools, do NOT claim to edit files.',
    '- Instead, return either:',
    '  1) the complete updated file content, or',
    '  2) exact line replacements using this format: LINE <number>: <new content>.',
    '- Keep your response focused on the edit content only.',
  }, '\n')
end

local function build_context_section(ctx, include_full_file)
  local lines = {
    'Context:',
    '- file: ' .. (ctx.file or ''),
    '- line: ' .. tostring(ctx.line or ''),
    '- col: ' .. tostring(ctx.col or ''),
    '- filetype: ' .. (ctx.filetype or ''),
    '- line_text: ' .. (ctx.line_text or ''),
    '- total_lines: ' .. tostring(ctx.total_lines or ''),
    '',
    'Nearby numbered lines (' .. tostring(ctx.snippet_start or '') .. '-' .. tostring(ctx.snippet_end or '') .. '):',
    ctx.snippet_text or '',
  }

  if (ctx.selected_text or '') ~= '' then
    table.insert(lines, '')
    table.insert(lines, 'Selected text (' .. tostring(ctx.selection_start_line or '') .. '-' .. tostring(ctx.selection_end_line or '') .. '):')
    table.insert(lines, ctx.selected_text)
  end

  if include_full_file and ctx.has_full_file_context and (ctx.full_file_text or '') ~= '' then
    table.insert(lines, '')
    table.insert(lines, 'Full file content:')
    table.insert(lines, ctx.full_file_text or '')
  end

  return table.concat(lines, '\n')
end

function M.fast(ctx)
  local include_full_file = ctx.has_full_file_context == true
  return table.concat({
    'Task: ' .. normalize_task(ctx.input),
    'Mode: Fast edit. Return only what is needed to apply the change.',
    build_edit_contract(ctx),
    '',
    build_context_section(ctx, include_full_file),
  }, '\n')
end

function M.deep(ctx)
  return table.concat({
    'Task: ' .. normalize_task(ctx.input),
    'Mode: Deep edit. Prioritize correctness, consistency, and minimal risk.',
    build_edit_contract(ctx),
    '',
    build_context_section(ctx, true),
  }, '\n')
end

return M
