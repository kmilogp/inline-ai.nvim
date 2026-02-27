# opencode.nvim

Neovim client for AI CLI agents (Opencode, Codex, Cursor Agent, and compatible tools).

## Requirements

- Neovim 0.10+
- At least one installed AI CLI provider (for example `opencode`, `codex`, or `cursor-agent`)

## Installation (lazy.nvim)

```lua
{
  'kmilogp/opencode.nvim',
}
```

## Basic usage

- `:OpencodePrompt [profile]`
- `<leader>o` opens the `fast` profile
- `<leader>O` opens the `deep` profile
- Legacy profile names `simple` and `complex` are still supported.

A profile chooses:

- provider CLI (`opencode`, `codex`, `cursor_agent`, etc.)
- model
- prompt template

## Configuration

Defaults are defined in `lua/opencode/init.lua`.

```lua
require('opencode').setup({
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
  },
  profiles = {
    fast = {
      provider = 'opencode',
      model = 'openai/gpt-5.1-codex-mini',
      template = function(ctx)
        return 'Task: ' .. ctx.input
      end,
    },
    deep = {
      provider = 'codex',
      model = 'openai/gpt-5.2-codex',
      template = function(ctx)
        return ('Task: %s\nFile: %s:%s'):format(ctx.input, ctx.file, ctx.line)
      end,
    },
  },
})
```

## Provider shape

Each provider entry supports:

- `cli_cmd` (string, required)
- `cli_args` (table, optional)
- `model_flag` (string, default: `--model`)
- `prompt_mode` (`'arg'` or `'stdin'`, default: `'arg'`)

The plugin shells out asynchronously via `vim.system` and shows stdout/stderr via `vim.notify`.
