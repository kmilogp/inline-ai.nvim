# opencode.nvim

Neovim client for Opencode with a small Node helper.

## Requirements

- Neovim 0.10+
- Node.js 22+ (uses `--experimental-strip-types` to run `.mts`)
- npm

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

## Server

The Node client connects to a fixed base URL (default `http://127.0.0.1:4096`).
If the server is not running, it uses the SDK to start it on the same host/port.
The server password is stored in `stdpath('data')/opencode/server.json` so all
Neovim clients reuse the same credentials.


## Commands

- `:OpencodePrompt [variant]`
- `:OpencodeInstall`

## Keymaps

- `<leader>o` opens the simple prompt
- `<leader>O` opens the complex prompt
