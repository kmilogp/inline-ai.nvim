# AGENTS.md

This repository is a small Neovim plugin that shells out to the Opencode CLI.
Use the notes below to keep changes consistent with existing patterns.

## Build, Lint, Test

There are no Makefile targets, tests, or CI workflows.

## Repository Layout

- `lua/opencode/init.lua`: main plugin module and core logic.
- `plugin/opencode.lua`: Neovim command + keymaps.
No additional scripts are required.

## Cursor / Copilot Rules

No Cursor rules found in `.cursor/rules/` or `.cursorrules`.
No Copilot rules found in `.github/copilot-instructions.md`.

If these files are added later, summarize them here verbatim.

## Code Style: General

- Keep edits minimal and consistent with surrounding code.
- Prefer small, focused helpers over large, complex functions.
- Favor early returns for guard clauses and error handling.
- Avoid adding comments unless they clarify non-obvious logic.
- Use ASCII-only text unless the file already includes Unicode.

## Code Style: Lua (Neovim)

- Indentation: 2 spaces.
- Quotes: single quotes for strings unless interpolation is clearer.
- Module pattern: `local M = {}` and `return M`.
- Functions: prefer `local function` for helpers; export via `M.*`.
- Tables: trailing commas are acceptable and used in config tables.
- Naming: `snake_case` for locals and functions (e.g., `get_line_text`).
- Neovim APIs: prefer `vim.api` and `vim.fn` consistently.
- Buffers/windows: validate handles before closing/deleting.
- JSON: use `vim.fn.json_encode/decode` with `pcall` guards.

Lua error handling patterns to keep:

- `pcall` around IO and JSON operations.
- Guarded returns when data is missing or invalid.
- Errors for unexpected state (e.g., unknown variant).
- `vim.notify` for user-facing failures or warnings.

## Formatting and Layout

- Keep line lengths reasonable; wrap tables/objects for readability.
- Align tables/objects vertically only when it improves clarity.
- Avoid deep nesting; extract helpers if needed.
- Favor explicit names over short abbreviations.

## Types and Data Shapes

- Lua config data is a plain table.
- When adding fields, keep `config` defaults centralized.

## Naming Conventions

- Lua: `snake_case` for locals, `PascalCase` not used.
- JS: `camelCase` for variables/functions, `PascalCase` for classes.
- Constants: only use `UPPER_SNAKE_CASE` if truly constant.
- Neovim commands: `Opencode*` prefix is consistent.
- Keymaps: keep descriptive `desc` strings.

## Error Handling and UX

- Prefer graceful failures with user-facing `vim.notify` messages.
- Log actionable details in errors (avoid generic "failed").
- For async results, always validate shapes before use.
- Keep error text stable to avoid surprising users.

## Neovim Plugin Behavior

- Prompt window is a minimal floating buffer; preserve UX.
- Keep prompt callback flow: build prompt -> set last_* -> send.
- The default variants are `fast` and `deep`.

## When Making Changes

- Update docs if you change commands, config, or behavior.
- Keep `plugin/` thin; put logic in `lua/opencode/`.
- Reuse existing helpers; do not duplicate `pcall` patterns.
- Respect existing UX (keymaps, prompts, notifications).
- Always run tests and confirm they pass before finishing work.

## Suggested Local Checks

 - Manual smoke check in Neovim after Lua edits.

## Gaps / TODOs

- No tests are present; add a test plan if you introduce tests.
- No formatter or lint rules are defined; keep style consistent.
- No CI is configured; document any new workflows you add.
