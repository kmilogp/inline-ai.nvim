local M = {}

local transport_cli = require("opencode.transport_cli")
local transport_server = require("opencode.transport_server")

local function plugin_root()
	local source = debug.getinfo(1, "S").source
	local path = source:sub(1, 1) == "@" and source:sub(2) or source
	return vim.fn.fnamemodify(path, ":p:h:h:h")
end

M._root = plugin_root()

M.last_prompt = nil
M.last_model = nil
M.last_variant = nil

local function opencode_data_path()
	local data_home = vim.fn.getenv("XDG_DATA_HOME")
	if data_home == vim.NIL or data_home == "" then
		data_home = vim.fn.expand("~/.local/share")
	end
	return data_home .. "/opencode"
end

M.config = {
	default_variant = "simple",
	base_url = "http://127.0.0.1:4096",
	transport = "cli",
	node_cmd = "node",
	node_args = { "--experimental-strip-types" },
	npm_cmd = "npm",
	client_script = plugin_root() .. "/scripts/opencode-client.ts",
	cli_cmd = "opencode",
	cli_args = { "run" },
	session_title = "Neovim",
	persist_sessions = true,
	sessions_file = vim.fn.stdpath("data") .. "/opencode/sessions.json",
	server_password_file = opencode_data_path() .. "/server.json",
	debug_log_file = opencode_data_path() .. "/opencode.nvim.log",
	server_config = {
		permission = {
			['*'] = 'deny',
			read = 'allow',
			edit = 'allow',
		},
		formatter = false,
		lsp = false,
		snapshot = false,
		agent = {
			build = {
				steps = 6,
				permission = {
					['*'] = 'deny',
					read = 'allow',
					edit = 'allow',
				},
			},
			title = {
				disable = true,
			},
			summary = {
				disable = true,
			},
			compaction = {
				disable = true,
			},
		},
	},
	variants = {
		simple = {
			model = "openai/gpt-5.1-codex-mini",
			template = function(ctx)
				return table.concat({
					"Task: " .. (ctx.input or ""),
					"Apply the change directly. Do not ask for confirmation.",
					"Use tools as needed to read and edit files.",
					"",
					"Context:",
					"- file: " .. (ctx.file or ""),
					"- line: " .. tostring(ctx.line or ""),
				}, "\n")
			end,
		},
		complex = {
			model = "openai/gpt-5.2-codex",
			template = function(ctx)
				return table.concat({
					"Task: " .. (ctx.input or ""),
					"",
					"Context:",
					"- file: " .. (ctx.file or ""),
					"- line: " .. tostring(ctx.line or ""),
					"- col: " .. tostring(ctx.col or ""),
					"- filetype: " .. (ctx.filetype or ""),
					"- line_text: " .. (ctx.line_text or ""),
				}, "\n")
			end,
		},
	},
}

M._sessions = nil

local function load_sessions()
	if not M.config.persist_sessions then
		return {}
	end
	local ok, lines = pcall(vim.fn.readfile, M.config.sessions_file)
	if not ok then
		return {}
	end
	local content = table.concat(lines, "\n")
	if content == "" then
		return {}
	end
	local ok_decode, decoded = pcall(vim.fn.json_decode, content)
	if ok_decode and type(decoded) == "table" then
		return decoded
	end
	return {}
end

local function save_sessions()
	if not M.config.persist_sessions then
		return
	end
	local dir = vim.fn.fnamemodify(M.config.sessions_file, ":h")
	if dir ~= "" then
		pcall(vim.fn.mkdir, dir, "p")
	end
	local ok_encode, encoded = pcall(vim.fn.json_encode, M._sessions or {})
	if not ok_encode then
		return
	end
	pcall(vim.fn.writefile, { encoded }, M.config.sessions_file)
end

local function ensure_sessions()
	if M._sessions == nil then
		M._sessions = load_sessions()
	end
end

local function project_key()
	return vim.fn.getcwd()
end

function M.get_session_id()
	ensure_sessions()
	return M._sessions[project_key()]
end

function M.set_session_id(id)
	ensure_sessions()
	M._sessions[project_key()] = id
	save_sessions()
end

local function get_line_text(bufnr, line)
	local lines = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)
	return lines[1] or ""
end

function M.get_context()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local file = vim.fn.expand("%:p")
	if file == "" then
		file = "[No Name]"
	else
		file = vim.fn.fnamemodify(file, ":.")
	end

	return {
		bufnr = bufnr,
		line = cursor[1],
		col = cursor[2] + 1,
		file = file,
		filetype = vim.bo[bufnr].filetype,
		line_text = get_line_text(bufnr, cursor[1]),
	}
end

function M.build_prompt(ctx, variant)
	local name = variant or M.config.default_variant
	local spec = M.config.variants[name]
	if not spec then
		error("opencode.build_prompt unknown variant: " .. tostring(name))
	end
	return spec.template(ctx)
end

local function resolve_transport()
	if M.config.transport == "cli" then
		return transport_cli
	end
	return transport_server
end

function M.install_deps()
	vim.notify("Opencode: installing npm dependencies...", vim.log.levels.INFO)
	local root = plugin_root()
	if vim.fn.filereadable(root .. "/package.json") ~= 1 then
		vim.notify("Opencode install failed: package.json not found", vim.log.levels.ERROR)
		return
	end

	local cmd = { M.config.npm_cmd, "install" }
	vim.system(cmd, { text = true, cwd = root }, function(obj)
		vim.schedule(function()
			if obj.code ~= 0 then
				local err = (obj.stderr and obj.stderr ~= "" and obj.stderr) or obj.stdout or "unknown error"
				vim.notify("Opencode install failed: " .. err, vim.log.levels.ERROR)
				return
			end
			vim.notify("Opencode dependencies installed", vim.log.levels.INFO)
		end)
	end)
end

function M.send_prompt(prompt, model, name)
	local label = name or M.config.default_variant
	local title = "Opencode (" .. label .. ")"
	local transport = resolve_transport()

	transport.send(M, prompt, model, function(ok, data, err)
		if not ok then
			vim.notify(err, vim.log.levels.ERROR, { title = title })
			return
		end
		local text = data.text or ""
		if text ~= "" then
			vim.notify(text, vim.log.levels.INFO, { title = title })
		end
	end)
end

function M.ensure_session(opts)
	opts = opts or {}
	local transport = resolve_transport()
	transport.ensure_session(M, opts)
end

local function create_prompt_window()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "prompt"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false

	local win_width = vim.api.nvim_win_get_width(0)
	local width = math.min(80, math.max(40, win_width - 4))

	local row = -1
	if vim.fn.line(".") <= 1 then
		row = 0
	end

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "cursor",
		row = row,
		col = 0,
		width = width,
		height = 1,
		style = "minimal",
		border = "rounded",
	})

	return buf, win
end

function M.open_prompt(variant, cb)
	if type(variant) == "function" and cb == nil then
		cb = variant
		variant = nil
	end

	if type(cb) ~= "function" then
		error("opencode.open_prompt expects a callback function")
	end

	local ctx = M.get_context()
	local buf, win = create_prompt_window()

	local function close_prompt()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end

	vim.fn.prompt_setprompt(buf, "Opencode: ")

	vim.keymap.set("i", "<C-c>", close_prompt, { buffer = buf, silent = true })
	vim.keymap.set("n", "<Esc>", close_prompt, { buffer = buf, silent = true })

	vim.fn.prompt_setcallback(buf, function(input)
		local prompt = M.build_prompt(vim.tbl_extend("force", ctx, { input = input or "" }), variant)
		local name = variant or M.config.default_variant
		local spec = M.config.variants[name] or {}
		local model = spec.model

		M.last_prompt = prompt
		M.last_model = model
		M.last_variant = name

		cb(prompt, model, name)
		close_prompt()
	end)

	vim.fn.prompt_setinterrupt(buf, function()
		close_prompt()
	end)

	vim.cmd("startinsert")
end

return M
