local M = {}

local function get_line_text(bufnr, line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)
  return lines[1] or ''
end

function M.get(templates, include_full_file_context, run_opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local file_context = templates.build_file_context(bufnr, cursor[1], include_full_file_context)
  local selection = run_opts and run_opts.selection or nil
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
    total_lines = file_context.total_lines,
    snippet_start = file_context.snippet_start,
    snippet_end = file_context.snippet_end,
    snippet_text = file_context.snippet_text,
    full_file_text = file_context.full_file_text,
    has_full_file_context = file_context.has_full_file_context,
    selected_text = selection and selection.text or nil,
    selection_start_line = selection and selection.start_line or nil,
    selection_end_line = selection and selection.end_line or nil,
  }
end

return M
