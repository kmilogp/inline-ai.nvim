local M = {}
local util = require('inline_ai.util')

local next_edit_id = 0

local function round_seconds(value)
  return math.floor(value * 1000 + 0.5) / 1000
end

local function append_log(path, message)
  pcall(vim.fn.writefile, { message }, path, 'a')
end

local function log_debug(state, message)
  local path = state.config.debug_log_file
  if not path or path == '' then
    return
  end

  if vim.in_fast_event and vim.in_fast_event() then
    vim.schedule(function()
      append_log(path, message)
    end)
    return
  end

  append_log(path, message)
end

local function log_event(state, event, payload)
  local entry = vim.tbl_extend('force', payload or {}, {
    event = event,
    ts = os.date('!%Y-%m-%dT%H:%M:%SZ'),
  })
  local ok, encoded = pcall(vim.fn.json_encode, entry)
  if ok and type(encoded) == 'string' then
    log_debug(state, encoded)
  end
end

function M.start_edit(state, profile_name, provider_name, model, prompt, ctx)
  next_edit_id = next_edit_id + 1
  state.last_edit_session = {
    edit_id = next_edit_id,
    started_at_ms = util.now_ms(),
    profile = profile_name,
    provider = provider_name,
    model = model,
    prompt_chars = #(prompt or ''),
    file = ctx and ctx.file or nil,
    line = ctx and ctx.line or nil,
    col = ctx and ctx.col or nil,
  }
end

function M.end_edit(state, status, details)
  local session = state.last_edit_session
  local ended_at = util.now_ms()
  local started_at = session and session.started_at_ms or nil
  local elapsed_ms = nil
  local elapsed_seconds = nil

  if type(started_at) == 'number' and started_at > 0 then
    elapsed_ms = math.max(0, ended_at - started_at)
    elapsed_seconds = round_seconds(elapsed_ms / 1000)
  end

  local base = {
    edit_id = session and session.edit_id or nil,
    profile = session and session.profile or nil,
    provider = session and session.provider or nil,
    model = session and session.model or nil,
    prompt_chars = session and session.prompt_chars or nil,
    file = session and session.file or nil,
    line = session and session.line or nil,
    col = session and session.col or nil,
    status = status,
    duration_seconds = elapsed_seconds,
    duration_ms = elapsed_ms,
  }
  log_event(state, 'edit', vim.tbl_extend('force', base, details or {}))
  state.last_edit_session = nil
end

function M.log_ollama_response(state, text, transport_meta)
  local session = state.last_edit_session
  log_event(state, 'ollama_response', {
    edit_id = session and session.edit_id or nil,
    profile = session and session.profile or nil,
    provider = session and session.provider or nil,
    model = session and session.model or nil,
    response_chars = #(text or ''),
    response_text = text or '',
    transport = transport_meta,
  })
end

return M
