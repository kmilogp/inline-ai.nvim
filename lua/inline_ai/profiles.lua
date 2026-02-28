local M = {}

function M.resolve(config, profile_name, providers)
  local name = profile_name or config.default_profile
  local profile = config.profiles[name]
  if not profile then
    return nil, nil, nil, 'Unknown profile: ' .. tostring(name)
  end

  local provider_name = profile.provider
  if not provider_name or provider_name == '' then
    return nil, nil, nil, 'Profile "' .. tostring(name) .. '" has no provider configured'
  end

  local provider, provider_err = providers.resolve_provider(config, provider_name)
  if not provider then
    return nil, nil, nil, provider_err
  end

  return name, profile, provider, nil
end

function M.build_prompt(config, profile_name, ctx, providers)
  local name, profile, _, err = M.resolve(config, profile_name, providers)
  if err then
    error('inline_ai.build_prompt ' .. err)
  end

  if type(profile.template) ~= 'function' then
    error('inline_ai.build_prompt profile has no template function: ' .. tostring(name))
  end

  return profile.template(ctx)
end

return M
