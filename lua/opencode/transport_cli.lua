local M = {}

local function now_ms()
  local uv = vim.uv or vim.loop
  if uv and uv.hrtime then
    return math.floor(uv.hrtime() / 1000000)
  end
  return 0
end

local function command_preview(provider, model)
  local preview = { provider.cli_cmd }
  vim.list_extend(preview, provider.cli_args or {})

  if provider.prompt_mode ~= 'stdin' then
    table.insert(preview, '<prompt>')
  end

  if model and model ~= '' then
    table.insert(preview, provider.model_flag or '--model')
    table.insert(preview, model)
  end

  return table.concat(preview, ' ')
end

local function append_prompt(cmd, provider, prompt)
  if provider.prompt_mode == 'stdin' then
    return
  end
  table.insert(cmd, prompt)
end

local function append_model(cmd, provider, model)
  if not model or model == '' then
    return
  end

  local model_flag = provider.model_flag or '--model'
  table.insert(cmd, model_flag)
  table.insert(cmd, model)
end

function M.send(_, provider, prompt, model, cb)
  local started_at = now_ms()

  local cmd = { provider.cli_cmd }
  vim.list_extend(cmd, provider.cli_args or {})

  if prompt == nil then
    prompt = ''
  end

  append_prompt(cmd, provider, prompt)
  append_model(cmd, provider, model)

  local system_opts = { text = true }
  if provider.prompt_mode == 'stdin' then
    system_opts.stdin = prompt
  end

  vim.system(cmd, system_opts, function(obj)
    local status_code = obj.code or -1
    local elapsed_ms = math.max(0, now_ms() - started_at)
    local signal = obj.signal
    if signal == vim.NIL then
      signal = nil
    end

    local meta = {
      provider_cmd = provider.cli_cmd,
      prompt_mode = provider.prompt_mode,
      model = model,
      prompt_chars = #prompt,
      command_preview = command_preview(provider, model),
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

      cb(true, { text = obj.stdout or '' }, nil, meta)
    end)
  end)
end

return M
