local M = {}
local default_prompts = require('inline_ai.default_prompts')

local function trim(value)
  local text = tostring(value or '')
  text = text:gsub('^%s+', '')
  text = text:gsub('%s+$', '')
  return text
end

local function normalize_prompt_item(item, index)
  if type(item) ~= 'table' then
    return nil, 'Invalid predefined prompt at index ' .. tostring(index) .. ': expected table'
  end

  local prompt = item.prompt
  if type(prompt) ~= 'string' or trim(prompt) == '' then
    return nil, 'Invalid predefined prompt at index ' .. tostring(index) .. ': missing prompt'
  end

  local title = item.title or item.name or prompt
  if type(title) ~= 'string' or trim(title) == '' then
    return nil, 'Invalid predefined prompt at index ' .. tostring(index) .. ': invalid title'
  end

  local profile = item.profile or item.agent or 'fast'
  if type(profile) ~= 'string' or trim(profile) == '' then
    return nil, 'Invalid predefined prompt at index ' .. tostring(index) .. ': invalid profile'
  end

  local description = item.description
  if description ~= nil and type(description) ~= 'string' then
    return nil, 'Invalid predefined prompt at index ' .. tostring(index) .. ': invalid description'
  end

  return {
    title = title,
    prompt = prompt,
    profile = profile,
    description = description or '',
  }, nil
end

function M.normalize(data)
  if type(data) ~= 'table' then
    return nil, 'Predefined prompts file must return a table'
  end

  local raw_prompts = data.prompts or data
  if type(raw_prompts) ~= 'table' then
    return nil, 'Predefined prompts must be a list table'
  end

  local prompts = {}
  for index, item in ipairs(raw_prompts) do
    local normalized, err = normalize_prompt_item(item, index)
    if err then
      return nil, err
    end
    prompts[#prompts + 1] = normalized
  end

  if #prompts == 0 then
    return nil, 'No predefined prompts found'
  end

  return prompts, nil
end

function M.load(config)
  local built_in, built_in_err = M.normalize(default_prompts.list())
  if built_in_err then
    return nil, 'Invalid built-in predefined prompts: ' .. built_in_err
  end

  local custom_prompts = config and config.predefined_prompts or nil
  if custom_prompts == nil then
    return built_in, nil, 'built-in defaults'
  end

  if type(custom_prompts) ~= 'table' then
    return nil, 'predefined_prompts must be a table'
  end

  if next(custom_prompts) == nil then
    return built_in, nil, 'built-in defaults'
  end

  local prompts, normalize_err = M.normalize(custom_prompts)
  if normalize_err then
    return nil, normalize_err
  end

  local merged = {}
  for _, item in ipairs(built_in) do
    merged[#merged + 1] = item
  end
  for _, item in ipairs(prompts) do
    merged[#merged + 1] = item
  end

  return merged, nil, 'built-in defaults + config.predefined_prompts'
end

return M
