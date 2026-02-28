local M = {}
local util = require('opencode.util')

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
  local started_at = util.now_ms()

  if not model or model == '' then
    cb(false, nil, 'Ollama provider requires a model', nil)
    return
  end

  prompt = util.normalize_prompt(prompt)

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
    local meta, status_code = util.build_system_meta({
      provider_cmd = 'ollama_http',
      provider_endpoint = provider.endpoint,
      model = model,
    }, obj, started_at, #prompt)

    vim.schedule(function()
      if status_code ~= 0 then
        local err = util.transport_error(obj)
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
