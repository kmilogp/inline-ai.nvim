local M = {}

local function copy_table(value)
  if type(value) ~= 'table' then
    return value
  end

  local result = {}
  for key, item in pairs(value) do
    result[key] = copy_table(item)
  end
  return result
end

local default_providers = {
  opencode = {
    cli_cmd = 'opencode',
    cli_args = { 'run' },
    model_flag = '--model',
    prompt_mode = 'arg',
  },
  codex = {
    cli_cmd = 'codex',
    cli_args = { 'exec' },
    model_flag = '--model',
    prompt_mode = 'arg',
  },
  cursor_agent = {
    cli_cmd = 'cursor-agent',
    cli_args = { '--trust' },
    model_flag = '--model',
    prompt_mode = 'arg',
  },
}

function M.default_providers()
  return copy_table(default_providers)
end

function M.resolve_provider(config, provider_name)
  if not provider_name or provider_name == '' then
    return nil, 'Provider is required'
  end

  local providers = (config and config.providers) or {}
  local provider = providers[provider_name]
  if not provider then
    return nil, 'Unknown provider: ' .. provider_name
  end

  local merged = vim.tbl_deep_extend('force', copy_table(default_providers[provider_name] or {}), provider)
  if not merged.cli_cmd or merged.cli_cmd == '' then
    return nil, 'Provider "' .. provider_name .. '" has no cli_cmd configured'
  end

  if type(merged.cli_args) ~= 'table' then
    merged.cli_args = {}
  end

  if merged.prompt_mode ~= 'arg' and merged.prompt_mode ~= 'stdin' then
    return nil, 'Provider "' .. provider_name .. '" has invalid prompt_mode: ' .. tostring(merged.prompt_mode)
  end

  return merged, nil
end

return M
