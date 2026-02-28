local M = {}

local providers = require('inline_ai.providers')
local templates = require('inline_ai.templates')
local defaults = require('inline_ai.defaults')
local logging = require('inline_ai.logging')
local context = require('inline_ai.context')
local profiles = require('inline_ai.profiles')
local edit_blocks = require('inline_ai.edit_blocks')
local sender = require('inline_ai.sender')
local transport_cli = require('inline_ai.transport_cli')
local transport_ollama = require('inline_ai.transport_ollama')

M.last_prompt = nil
M.last_model = nil
M.last_profile = nil
M.last_provider = nil
M.last_context = nil
M.last_edit_session = nil

M.config = defaults.build(templates, providers)

function M.setup(opts)
  if type(opts) ~= 'table' then
    return
  end
  M.config = vim.tbl_deep_extend('force', M.config, opts)
end

function M.get_context(include_full_file_context, run_opts)
  return context.get(templates, include_full_file_context, run_opts)
end

function M.build_prompt(ctx, profile_name)
  return profiles.build_prompt(M.config, profile_name, ctx, providers)
end

local function resolve_profile(profile_name)
  return profiles.resolve(M.config, profile_name, providers)
end

local function apply_prompt_input(input, name, profile, provider, run_opts)
  local include_full_file = profile.include_full_file_context ~= false
  local ctx = M.get_context(include_full_file, run_opts)
  local prompt_ctx = vim.tbl_extend('force', ctx, {
    input = input or '',
    provider_transport = provider.transport,
  })
  local prompt = M.build_prompt(prompt_ctx, name)
  local model = profile.model

  M.last_prompt = prompt
  M.last_model = model
  M.last_profile = name
  M.last_provider = profile.provider
  M.last_context = ctx
  logging.start_edit(M, name, profile.provider, model, prompt, ctx)

  return prompt, model
end

function M.run_prompt(input, profile_name, run_opts)
  local name, profile, provider, err = resolve_profile(profile_name)
  if err then
    vim.notify(err, vim.log.levels.ERROR, { title = 'Inline AI' })
    return
  end

  local prompt, model = apply_prompt_input(input, name, profile, provider, run_opts)
  M.send_prompt(prompt, model, name, profile.provider)
end

function M.send_prompt(prompt, model, profile_name, provider_name)
  sender.send(M, {
    providers = providers,
    profiles = profiles,
    logging = logging,
    edit_blocks = edit_blocks,
    transport_cli = transport_cli,
    transport_ollama = transport_ollama,
  }, prompt, model, profile_name, provider_name)
end

return M
