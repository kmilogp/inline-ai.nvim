local M = {}

local function inline_ai_data_path()
  local data_home = vim.fn.getenv('XDG_DATA_HOME')
  if data_home == vim.NIL or data_home == '' then
    data_home = vim.fn.expand('~/.local/share')
  end
  return data_home .. '/inline-ai'
end

function M.build(templates, providers)
  return {
    default_profile = 'fast',
    debug_log_file = inline_ai_data_path() .. '/inline-ai.nvim.log',
    providers = providers.default_providers(),
    profiles = {
      fast = {
        provider = 'ollama',
        model = 'qwen3-coder',
        include_full_file_context = true,
        template = templates.fast,
      },
      deep = {
        provider = 'opencode',
        model = 'openai/gpt-5.2-codex',
        include_full_file_context = true,
        template = templates.deep,
      },
    },
  }
end

return M
