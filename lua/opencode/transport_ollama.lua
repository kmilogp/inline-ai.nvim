local M = {}

local function now_ms()
  local uv = vim.uv or vim.loop
  if uv and uv.hrtime then
    return math.floor(uv.hrtime() / 1000000)
  end
  return 0
end

local function build_payload(provider, prompt, model)
  local payload = {
    model = model,
    prompt = prompt,
  }

  local options = provider.options or {}
  for key, value in pairs(options) do
    payload[key] = value
  end

  if payload.stream == nil then
    payload.stream = false
  end

  return payload
end

function M.send(_, provider, prompt, model, cb)
  local started_at = now_ms()

  if not model or model == '' then
    cb(false, nil, 'Ollama provider requires a model', nil)
    return
  end

  if prompt == nil then
    prompt = ''
  end

  local payload = build_payload(provider, prompt, model)
  local ok, body = pcall(vim.fn.json_encode, payload)
  if not ok or type(body) ~= 'string' then
    cb(false, nil, 'Failed to encode Ollama request payload', nil)
    return
  end

  local cmd = {
    'curl',
    '-sS',
    '-X',
    'POST',
    provider.endpoint,
    '-H',
    'Content-Type: application/json',
    '-d',
    body,
  }

  if type(provider.timeout_seconds) == 'number' and provider.timeout_seconds > 0 then
    table.insert(cmd, 2, tostring(provider.timeout_seconds))
    table.insert(cmd, 2, '--max-time')
  end

  vim.system(cmd, { text = true }, function(obj)
    local status_code = obj.code or -1
    local elapsed_ms = math.max(0, now_ms() - started_at)
    local signal = obj.signal
    if signal == vim.NIL then
      signal = nil
    end

    local meta = {
      provider_cmd = 'ollama_http',
      provider_endpoint = provider.endpoint,
      model = model,
      prompt_chars = #prompt,
      status = status_code == 0 and 'ok' or 'error',
      status_code = status_code,
      elapsed_ms = elapsed_ms,
      signal = signal,
      stdout_chars = #(obj.stdout or ''),
      stderr_chars = #(obj.stderr or ''),
    }

    vim.schedule(function()
      if status_code ~= 0 then
        local err = (obj.stderr and obj.stderr ~= '' and obj.stderr) or obj.stdout or 'unknown error'
        cb(false, nil, err, meta)
        return
      end

      local decoded_ok, decoded = pcall(vim.fn.json_decode, obj.stdout or '')
      if not decoded_ok or type(decoded) ~= 'table' then
        cb(false, nil, 'Failed to decode Ollama response', meta)
        return
      end

      if decoded.error and decoded.error ~= '' then
        cb(false, nil, decoded.error, meta)
        return
      end

      cb(true, { text = decoded.response or '' }, nil, meta)
    end)
  end)
end

return M
