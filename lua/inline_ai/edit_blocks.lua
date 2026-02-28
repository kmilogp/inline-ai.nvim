local M = {}

local function normalize_control_line(line)
  local value = tostring(line or '')
  value = value:gsub('\r$', '')
  value = value:gsub('^%s+', '')
  value = value:gsub('%s+$', '')
  return value
end

local function find_block_matches(source_lines, needle_lines)
  local matches = {}
  local needle_len = #needle_lines
  local max_start = #source_lines - needle_len + 1
  if needle_len == 0 or max_start < 1 then
    return matches
  end

  for start_idx = 1, max_start do
    local matched = true
    for offset = 1, needle_len do
      if source_lines[start_idx + offset - 1] ~= needle_lines[offset] then
        matched = false
        break
      end
    end
    if matched then
      table.insert(matches, start_idx)
    end
  end

  return matches
end

local function strip_number_prefix(line)
  local stripped = line:match('^%s*%d+:%s?(.*)$')
  if stripped ~= nil then
    return stripped, true
  end
  return line, false
end

local function strip_trailing_whitespace(line)
  return tostring(line or ''):gsub('%s+$', '')
end

local function build_anchor_variants(anchor_lines)
  local variants = { anchor_lines }
  local stripped = {}
  local changed = false

  for i, line in ipairs(anchor_lines) do
    local normalized, had_prefix = strip_number_prefix(line)
    stripped[i] = normalized
    if had_prefix then
      changed = true
    end
  end

  if changed then
    table.insert(variants, stripped)
  end

  local rstripped = {}
  local trailing_changed = false
  for i, line in ipairs(anchor_lines) do
    local normalized = strip_trailing_whitespace(line)
    rstripped[i] = normalized
    if normalized ~= line then
      trailing_changed = true
    end
  end

  if trailing_changed then
    table.insert(variants, rstripped)
  end

  return variants
end

local function normalize_numbered_lines(lines)
  local out = {}
  for i, line in ipairs(lines) do
    local normalized = strip_number_prefix(line)
    out[i] = normalized
  end
  return out
end

local function trim_trailing_empty_lines(lines)
  local last = #lines
  while last > 0 and lines[last] == '' do
    last = last - 1
  end

  local out = {}
  for i = 1, last do
    out[i] = lines[i]
  end
  return out
end

local function normalize_insert_anchor_lines(lines)
  local normalized = normalize_numbered_lines(lines)
  local trimmed = trim_trailing_empty_lines(normalized)
  if #trimmed > 0 then
    return trimmed
  end
  if #normalized > 0 then
    return { '' }
  end
  return {}
end

local function build_line_counts(lines)
  local counts = {}
  for _, line in ipairs(lines) do
    counts[line] = (counts[line] or 0) + 1
  end
  return counts
end

local function is_replace_already_applied(source_lines, block)
  local new_matches = {}
  local variants = build_anchor_variants(block.new_lines)
  for _, variant in ipairs(variants) do
    new_matches = find_block_matches(source_lines, variant)
    if #new_matches > 0 then
      break
    end
  end
  if #new_matches == 0 then
    return false
  end

  local source_counts = build_line_counts(source_lines)
  local old_counts = build_line_counts(block.anchor_lines)
  local new_counts = build_line_counts(block.new_lines)

  for line, count in pairs(new_counts) do
    old_counts[line] = math.max(0, (old_counts[line] or 0) - count)
  end

  for line, remaining in pairs(old_counts) do
    if remaining > 0 and (source_counts[line] or 0) > 0 then
      return false
    end
  end

  return true
end

local function find_anchor_matches(source_lines, anchor_lines)
  local variants = build_anchor_variants(anchor_lines)
  for _, variant in ipairs(variants) do
    local matches = find_block_matches(source_lines, variant)
    if #matches > 0 then
      return matches
    end
  end
  return {}
end

local function replace_range(source_lines, start_idx, end_idx, new_lines)
  local out = {}
  for i = 1, start_idx - 1 do
    table.insert(out, source_lines[i])
  end
  for _, line in ipairs(new_lines) do
    table.insert(out, line)
  end
  for i = end_idx + 1, #source_lines do
    table.insert(out, source_lines[i])
  end
  return out
end

local function apply_block(source_lines, block, start_idx)
  local end_idx = start_idx + #block.anchor_lines - 1
  if block.kind == 'replace' then
    return replace_range(source_lines, start_idx, end_idx, block.new_lines), nil
  end

  if block.kind == 'insert' then
    local insert_at = start_idx - 1
    if block.position == 'after' then
      insert_at = end_idx
    end
    return replace_range(source_lines, insert_at + 1, insert_at, block.new_lines), nil
  end

  return nil, 'Cannot auto-apply: unknown block type'
end

function M.parse(text)
  local lines = vim.split(text or '', '\n', { plain = true })
  local blocks = {}
  local index = 1

  local function collect_until(stop_token)
    local collected = {}
    while index <= #lines and normalize_control_line(lines[index]) ~= stop_token do
      table.insert(collected, lines[index])
      index = index + 1
    end
    if normalize_control_line(lines[index]) ~= stop_token then
      return nil
    end
    index = index + 1
    return collected
  end

  while index <= #lines do
    local line = normalize_control_line(lines[index])
    if line == '' then
      index = index + 1
    elseif line == 'BEGIN_REPLACE' then
      index = index + 1
      if normalize_control_line(lines[index]) ~= 'OLD:' then
        return nil, 'Cannot auto-apply: expected OLD: after BEGIN_REPLACE'
      end
      index = index + 1

      local old_lines = collect_until('NEW:')
      if not old_lines then
        return nil, 'Cannot auto-apply: expected NEW: block'
      end
      old_lines = trim_trailing_empty_lines(normalize_numbered_lines(old_lines))

      local new_lines = collect_until('END_REPLACE')
      if not new_lines then
        return nil, 'Cannot auto-apply: expected END_REPLACE marker'
      end
      new_lines = trim_trailing_empty_lines(normalize_numbered_lines(new_lines))

      if #old_lines == 0 then
        return nil, 'Cannot auto-apply: OLD block cannot be empty'
      end

      table.insert(blocks, {
        kind = 'replace',
        anchor_lines = old_lines,
        new_lines = new_lines,
      })
    elseif line == 'BEGIN_INSERT' then
      index = index + 1

      local position_line = normalize_control_line(lines[index])
      local position = nil
      if position_line == 'BEFORE:' then
        position = 'before'
      elseif position_line == 'AFTER:' then
        position = 'after'
      else
        return nil, 'Cannot auto-apply: expected BEFORE: or AFTER: after BEGIN_INSERT'
      end
      index = index + 1

      local anchor_lines = collect_until('NEW:')
      if not anchor_lines then
        return nil, 'Cannot auto-apply: expected NEW: block in insert'
      end
      anchor_lines = normalize_insert_anchor_lines(anchor_lines)
      if #anchor_lines == 0 then
        return nil, 'Cannot auto-apply: insert anchor block cannot be empty'
      end

      local new_lines = collect_until('END_INSERT')
      if not new_lines then
        return nil, 'Cannot auto-apply: expected END_INSERT marker'
      end
      new_lines = trim_trailing_empty_lines(normalize_numbered_lines(new_lines))
      if #new_lines == 0 then
        return nil, 'Cannot auto-apply: insert NEW block cannot be empty'
      end

      table.insert(blocks, {
        kind = 'insert',
        position = position,
        anchor_lines = anchor_lines,
        new_lines = new_lines,
      })
    else
      return nil, 'Cannot auto-apply: unexpected content outside edit block'
    end
  end

  if #blocks == 0 then
    return nil, 'Cannot auto-apply: no edit blocks found'
  end

  return blocks, nil
end

function M.apply(ctx, blocks)
  local bufnr = ctx and ctx.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false, 'Cannot auto-apply: target buffer is not available', 0
  end

  if not vim.bo[bufnr].modifiable then
    return false, 'Cannot auto-apply: target buffer is not modifiable', 0
  end

  if #blocks == 0 then
    return false, 'Cannot auto-apply: no edit blocks found', 0
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local source_lines = vim.api.nvim_buf_get_lines(bufnr, 0, line_count, false)
  local applied_count = 0
  local skipped_count = 0

  for block_index, block in ipairs(blocks) do
    local matches = find_anchor_matches(source_lines, block.anchor_lines)
    local skip_block = false
    if #matches == 0 then
      if block.kind == 'replace' and #block.new_lines > 0 then
        if is_replace_already_applied(source_lines, block) then
          skipped_count = skipped_count + 1
          skip_block = true
        end
      end
      if not skip_block then
        return false, 'Cannot auto-apply: anchor block not found for block ' .. tostring(block_index), block_index
      end
    end
    if (not skip_block) and #matches > 1 then
      return false, 'Cannot auto-apply: anchor block is ambiguous for block ' .. tostring(block_index), block_index
    end

    if not skip_block then
      local out, apply_err = apply_block(source_lines, block, matches[1])
      if not out then
        return false, (apply_err or 'Cannot auto-apply: unknown error') .. ' for block ' .. tostring(block_index), block_index
      end
      source_lines = out
      applied_count = applied_count + 1
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, source_lines)

  if skipped_count > 0 then
    return true, 'Applied ' .. tostring(applied_count) .. ' edit block(s), skipped ' .. tostring(skipped_count) .. ' already-applied block(s)', applied_count
  end

  return true, 'Applied ' .. tostring(applied_count) .. ' edit block(s)', applied_count
end

return M
