local M = {}

local function resolve_transport(provider, transport_cli, transport_ollama)
  if provider and provider.transport == 'ollama_http' then
    return transport_ollama
  end
  return transport_cli
end

local function reload_target_buffer(state)
  local ctx = state and state.last_context
  local bufnr = ctx and ctx.bufnr
  if type(bufnr) ~= 'number' or bufnr <= 0 then
    return
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  pcall(vim.cmd, 'checktime ' .. tostring(bufnr))
end

function M.send(state, deps, prompt, model, profile_name, provider_name)
  local name, profile, provider, err = deps.profiles.resolve(state.config, profile_name, deps.providers)
  if err then
    deps.logging.end_edit(state, 'error', { phase = 'resolve_profile', error = err })
    vim.notify(err, vim.log.levels.ERROR, { title = 'Inline AI' })
    return
  end

  if provider_name and provider_name ~= '' and provider_name ~= profile.provider then
    deps.logging.end_edit(state, 'error', { phase = 'provider_mismatch', error = provider_name .. ' vs ' .. profile.provider })
    vim.notify('Profile/provider mismatch: ' .. provider_name .. ' vs ' .. profile.provider, vim.log.levels.ERROR, { title = 'Inline AI' })
    return
  end

  local resolved_model = model or profile.model
  local title = 'Inline AI (' .. name .. ' / ' .. profile.provider .. ')'
  local transport = resolve_transport(provider, deps.transport_cli, deps.transport_ollama)

  transport.send(state, provider, prompt, resolved_model, function(ok, data, transport_err, transport_meta)
    if not ok then
      deps.logging.end_edit(state, 'error', {
        phase = 'provider_response',
        provider = profile.provider,
        error = transport_err,
        transport = transport_meta,
      })
      vim.notify(transport_err, vim.log.levels.ERROR, { title = title })
      return
    end

    local text = data.text or ''
    if text == '' then
      if provider.transport == 'cli' then
        reload_target_buffer(state)
      end
      deps.logging.end_edit(state, 'ok', {
        provider = profile.provider,
        apply_mode = 'empty_response',
        transport = transport_meta,
      })
      return
    end

    if provider.transport ~= 'ollama_http' then
      reload_target_buffer(state)
      deps.logging.end_edit(state, 'ok', {
        provider = profile.provider,
        apply_mode = 'provider_output',
        transport = transport_meta,
      })
      vim.notify(text, vim.log.levels.INFO, { title = title })
      return
    end

    deps.logging.log_ollama_response(state, text, transport_meta)
    local blocks, parse_err = deps.edit_blocks.parse(text)
    local ok_apply, apply_msg, applied_count = false, parse_err, 0
    if blocks then
      ok_apply, apply_msg, applied_count = deps.edit_blocks.apply(state.last_context, blocks)
    end

    if ok_apply then
      deps.logging.end_edit(state, 'ok', {
        provider = profile.provider,
        apply_mode = 'auto',
        apply_result = apply_msg,
        edit_block_count = #blocks,
        applied_block_count = applied_count,
        transport = transport_meta,
      })
      vim.notify(apply_msg, vim.log.levels.INFO, { title = title })
      return
    end

    deps.logging.end_edit(state, 'error', {
      provider = profile.provider,
      apply_mode = 'auto',
      apply_result = apply_msg,
      edit_block_count = blocks and #blocks or 0,
      transport = transport_meta,
    })
    vim.notify(apply_msg, vim.log.levels.ERROR, { title = title })
  end)
end

return M
