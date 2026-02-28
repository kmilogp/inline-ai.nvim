# inline-ai.nvim

Neovim client for AI agents (Opencode, Codex, Cursor Agent, Ollama, and compatible tools).

## Requirements

- Neovim 0.10+
- At least one configured provider (for example `opencode`, `codex`, `cursor-agent`, or `ollama`)
- `curl` is required when using the Ollama HTTP transport

## Installation (lazy.nvim)

```lua
{
  'kmilogp/inline-ai.nvim',
}
```

## Tests

- Run unit tests: `lua tests/lua/run.lua`

## Basic usage

- `:InlineAiPrompt [profile] <prompt>`
- `<leader>of` (normal + visual) pre-fills `:InlineAiPrompt fast ` in the command line
- `<leader>od` (normal + visual) pre-fills `:InlineAiPrompt deep ` in the command line
- `<leader>op` (normal + visual) pre-fills `:InlineAiPrompt <default_profile> ` in the command line
- Visual-mode usage is supported via range commands (for example `:'<,'>InlineAiPrompt fast ...`); the selected lines are included in prompt context.

A profile chooses:

- provider (`opencode`, `codex`, `cursor_agent`, `ollama`, etc.)
- model
- prompt template
- `include_full_file_context` (optional; controls full-file prompt payload)

Built-in templates include editing context (cursor location and numbered nearby lines). By default, all built-in profiles include full file content to reduce follow-up searching; set `include_full_file_context = false` on a profile if you want smaller prompts and lower latency.

## Configuration

Defaults are defined in `lua/inline_ai/init.lua`.

```lua
require('inline_ai').setup({
  default_profile = 'fast',
  providers = {
    opencode = {
      cli_cmd = 'opencode',
      cli_args = { 'run' },
      model_flag = '--model',
      prompt_mode = 'arg', -- or 'stdin'
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
    ollama = {
      transport = 'ollama_http',
      endpoint = 'http://127.0.0.1:11434/api/generate',
      options = { stream = false, keep_alive = -1 },
    },
  },
  profiles = {
    fast = {
      provider = 'ollama',
      model = 'qwen3-coder',
      include_full_file_context = true,
      template = function(ctx)
        return 'Task: ' .. ctx.input
      end,
    },
    deep = {
      provider = 'codex',
      model = 'openai/gpt-5.2-codex',
      include_full_file_context = true,
      template = function(ctx)
        return ('Task: %s\nFile: %s:%s'):format(ctx.input, ctx.file, ctx.line)
      end,
    },
    local = {
      provider = 'ollama',
      model = 'qwen3-coder',
      auto_apply = true,
      include_full_file_context = true,
      template = function(ctx)
        return ('Task: %s\nFile: %s:%s'):format(ctx.input, ctx.file, ctx.line)
      end,
    },
  },
})
```

## Provider shape

CLI providers support:

- `cli_cmd` (string, required)
- `cli_args` (table, optional)
- `model_flag` (string, default: `--model`)
- `prompt_mode` (`'arg'` or `'stdin'`, default: `'arg'`)

`ollama_http` providers support:

- `transport` (`'ollama_http'`, required)
- `endpoint` (string, required, usually `http://127.0.0.1:11434/api/generate`)
- `options` (table, optional; merged into the JSON body)
- `timeout_seconds` (number, optional)
- `auto_apply` (boolean, optional; when true, the plugin applies parsed edits automatically)

The plugin shells out asynchronously via `vim.system` and shows provider output via `vim.notify`.

For `ollama_http`, set `auto_apply = true` to apply model edits automatically.

When `auto_apply = true`, the model output must contain only edit blocks in one of these formats:

```text
BEGIN_REPLACE
OLD:
<exact current lines to replace>
NEW:
<replacement lines; leave empty to delete the block>
END_REPLACE

BEGIN_INSERT
BEFORE: or AFTER:
<exact anchor lines that already exist>
NEW:
<new lines to insert>
END_INSERT
```

You can return multiple blocks one after another. Full-file replacements are not allowed in auto-apply mode.
Do not include numbered prefixes (for example `12: `) in `OLD` or insert anchor lines.
Blank-line insert anchors are allowed; if the blank line is not unique, include surrounding lines in the same anchor block.

## Request logs

Every edit operation is logged as one JSON line to `debug_log_file`.

- Default path: `$XDG_DATA_HOME/inline-ai/inline-ai.nvim.log`
- Fallback when `XDG_DATA_HOME` is unset: `~/.local/share/inline-ai/inline-ai.nvim.log`

Each edit operation writes exactly one JSON log line with fields like:

- `event` (`edit`), `ts`
- `edit_id`, `profile`, `provider`, `model`, `prompt_chars`
- `file`, `line`, `col`
- `status`, `duration_seconds`, `duration_ms`
- `transport` (provider execution details such as `status_code`, `elapsed_ms`, and output sizes)
- `apply_mode`, `apply_result`, `error` (when relevant)

For `ollama_http`, an additional JSON log line is written with `event = ollama_response`, containing `response_text` and `response_chars`.

To disable logging:

```lua
require('inline_ai').setup({
  debug_log_file = '',
})
```
