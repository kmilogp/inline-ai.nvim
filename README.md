# opencode.nvim

Neovim client for Opencode with a small Node helper.

## Requirements

- Neovim 0.10+
- Node.js and npm

## Installation (lazy.nvim)

Dependencies must be installed by lazy.nvim's build step:

```lua
{
  "kmilogp/opencode.nvim",
  build = "npm install",
}
```

If you already installed the plugin without dependencies, run:

```
:OpencodeInstall
```

## Configuration

Defaults are in `lua/opencode/init.lua`. You can override fields by editing
`require("opencode").config` in your config.


## Commands

- `:OpencodePrompt [variant]`
- `:OpencodeInstall`

## Keymaps

- `<leader>o` opens the simple prompt
- `<leader>O` opens the complex prompt
