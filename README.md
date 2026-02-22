# opencode.nvim

Neovim client for Opencode CLI.

## Requirements

- Neovim 0.10+
- `opencode` CLI

## Installation (lazy.nvim)

```lua
{
  "kmilogp/opencode.nvim",
}
```

## Configuration

Defaults are in `lua/opencode/init.lua`. You can override fields by editing
`require("opencode").config` in your config.

## CLI

The plugin runs:

```
opencode run "<prompt>" --model <model>
```

Configure the CLI command and args with `cli_cmd` and `cli_args` if needed.


## Commands

- `:OpencodePrompt [variant]`

## Keymaps

- `<leader>o` opens the simple prompt
- `<leader>O` opens the complex prompt
