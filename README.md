# inline-ai.nvim

Neovim client for AI agents (Opencode, Codex, Cursor Agent, Ollama, and compatible tools).

## Requirements

- Neovim 0.10+
- `nvim-telescope/telescope.nvim` (required for `:InlineAiPromptPicker`)
- At least one configured provider (for example `opencode`, `codex`, `cursor-agent`, or `ollama`)
- `curl` is required when using the Ollama HTTP transport

## Installation (lazy.nvim)

```lua
{
  'kmilogp/inline-ai.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',
  },
}
```

Lazy.nvim example with predefined prompts:

```lua
{
  'kmilogp/inline-ai.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',
  },
  opts = {
    default_profile = 'fast',
    predefined_prompts = {
      {
        title = 'Extract Function',
        prompt = 'Refactor current logic into a function. If inside a class, use a private method.',
        profile = 'fast',
      },
      {
        title = 'Deep Review',
        prompt = 'Review architecture and suggest concrete improvements.',
        agent = 'deep',
      },
    },
  },
}
```

## Tests

- Run unit tests: `lua tests/lua/run.lua`

## Basic usage

- `:InlineAiPrompt [profile] <prompt>`
- `:InlineAiPromptPicker` opens a Telescope picker with built-in prompts plus configured `predefined_prompts`
- `<leader>of` (normal + visual) pre-fills `:InlineAiPrompt fast ` in the command line
- `<leader>od` (normal + visual) pre-fills `:InlineAiPrompt deep ` in the command line
- `<leader>op` (normal + visual) opens `:InlineAiPromptPicker`
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
  predefined_prompts = {
    {
      title = 'Quick refactor',
      prompt = 'Refactor this file for clarity and keep behavior unchanged',
      profile = 'fast', -- optional, defaults to "fast"
      description = 'Safe cleanup pass', -- optional
    },
    {
      title = 'Deep architecture review',
      prompt = 'Review architecture and suggest concrete improvements',
      agent = 'deep', -- alias for profile
    },
  },
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
      include_full_file_context = true,
      template = function(ctx)
        return ('Task: %s\nFile: %s:%s'):format(ctx.input, ctx.file, ctx.line)
      end,
    },
  },
})
```

The picker always includes built-in prompts from `lua/inline_ai/default_prompts.lua`.
If `predefined_prompts` is set, its entries are appended to the built-in set.

## Passing prompts

Direct prompt from command line:

```vim
:InlineAiPrompt fast Refactor this block into a helper function
```

Predefined prompts via setup + picker:

```lua
require('inline_ai').setup({
  predefined_prompts = {
    {
      title = 'Extract Function',
      prompt = 'Refactor current logic into a function. If inside a class, use a private method.',
      profile = 'fast',
    },
  },
})
```

Then run `:InlineAiPromptPicker` (or `<leader>op`) and select the prompt.

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

The plugin shells out asynchronously via `vim.system` and shows provider output via `vim.notify`.

For `ollama_http`, the plugin always applies parsed edit blocks automatically.
The model output must contain only edit blocks in one of these formats:

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

You can return multiple blocks one after another. Full-file replacements are not allowed in this mode.
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
