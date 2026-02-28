local M = {}
local util = require('opencode.util')

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
  local started_at = util.now_ms()

  local cmd = { provider.cli_cmd }
  vim.list_extend(cmd, provider.cli_args or {})

  prompt = util.normalize_prompt(prompt)

  append_prompt(cmd, provider, prompt)
  append_model(cmd, provider, model)

  local system_opts = { text = true }
  if provider.prompt_mode == 'stdin' then
    system_opts.stdin = prompt
  end

  vim.system(cmd, system_opts, function(obj)
    local meta, status_code = util.build_system_meta({
      provider_cmd = provider.cli_cmd,
      prompt_mode = provider.prompt_mode,
      model = model,
      command_preview = command_preview(provider, model),
    }, obj, started_at, #prompt)

    vim.schedule(function()
      if status_code ~= 0 then
        local err = util.transport_error(obj)
        cb(false, nil, err, meta)
        return
      end

      cb(true, { text = obj.stdout or '' }, nil, meta)
    end)
  end)
end

return M
