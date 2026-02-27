local M = {}

local function log_debug(state, message)
  if not state.config.debug_log_file or state.config.debug_log_file == '' then
    return
  end
  pcall(vim.fn.writefile, { message }, state.config.debug_log_file, 'a')
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

function M.send(state, provider, prompt, model, cb)
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

  log_debug(state, 'running: ' .. table.concat(cmd, ' '))

  vim.system(cmd, system_opts, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        local err = (obj.stderr and obj.stderr ~= '' and obj.stderr) or obj.stdout or 'unknown error'
        cb(false, nil, err)
        return
      end

      cb(true, { text = obj.stdout or '' }, nil)
    end)
  end)
end

return M
