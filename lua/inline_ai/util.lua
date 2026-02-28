local M = {}

function M.now_ms()
  local uv = vim.uv or vim.loop
  if uv and uv.hrtime then
    return math.floor(uv.hrtime() / 1000000)
  end
  return 0
end

function M.normalize_prompt(prompt)
  if prompt == nil then
    return ''
  end
  return prompt
end

function M.normalize_signal(signal)
  if signal == vim.NIL then
    return nil
  end
  return signal
end

function M.transport_error(obj)
  return (obj.stderr and obj.stderr ~= '' and obj.stderr) or obj.stdout or 'unknown error'
end

function M.build_system_meta(base, obj, started_at_ms, prompt_chars)
  local status_code = obj.code or -1
  local meta = vim.tbl_extend('force', base or {}, {
    prompt_chars = prompt_chars,
    status = status_code == 0 and 'ok' or 'error',
    status_code = status_code,
    elapsed_ms = math.max(0, M.now_ms() - started_at_ms),
    signal = M.normalize_signal(obj.signal),
    stdout_chars = #(obj.stdout or ''),
    stderr_chars = #(obj.stderr or ''),
  })
  return meta, status_code
end

return M
