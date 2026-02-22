local M = {}

local function resolve_root(state)
	if state._root then
		return state._root
	end
	local script = state.config.client_script
	if script and script ~= "" then
		return vim.fn.fnamemodify(script, ":h:h")
	end
	return vim.fn.getcwd()
end

local function run_client(state, payload, cb)
	local function decode_error(output)
		if not output or output == "" then
			return nil
		end
		local ok, decoded = pcall(vim.fn.json_decode, output)
		if ok and type(decoded) == "table" and decoded.error then
			return decoded.error
		end
		return nil
	end

	local root = resolve_root(state)
	if vim.fn.isdirectory(root .. "/node_modules") ~= 1 then
		cb(false, nil, 'Node dependencies missing. Set lazy.nvim build = "npm install" or run :OpencodeInstall.')
		return
	end
	local cmd = { state.config.node_cmd }
	if type(state.config.node_args) == "table" then
		vim.list_extend(cmd, state.config.node_args)
	end
	table.insert(cmd, state.config.client_script)
	vim.system(cmd, { text = true, stdin = payload }, function(obj)
		vim.schedule(function()
			if obj.code ~= 0 then
				local err = (obj.stderr and obj.stderr ~= "" and obj.stderr) or obj.stdout or "unknown error"
				local decoded = decode_error(obj.stdout) or decode_error(obj.stderr)
				if decoded then
					err = decoded
				end
				cb(false, nil, err)
				return
			end
			local ok, decoded = pcall(vim.fn.json_decode, obj.stdout or "")
			if not ok or type(decoded) ~= "table" then
				cb(false, nil, "Failed to decode opencode response")
				return
			end
			if decoded.ok == false then
				cb(false, decoded, decoded.error or "Opencode request failed")
				return
			end
			cb(true, decoded, nil)
		end)
	end)
end

function M.send(state, prompt, model, cb)
	local payload = {
		baseUrl = state.config.base_url,
		sessionId = state.get_session_id(),
		sessionTitle = state.config.session_title,
		directory = vim.fn.getcwd(),
		prompt = prompt,
		model = model,
		serverConfigFile = state.config.server_password_file,
		serverConfig = state.config.server_config,
		debugLogFile = state.config.debug_log_file,
	}

	run_client(state, vim.fn.json_encode(payload), function(ok, data, err)
		if ok and data.sessionId then
			state.set_session_id(data.sessionId)
		end
		cb(ok, data, err)
	end)
end

function M.ensure_session(state, opts)
	opts = opts or {}
	if state.get_session_id() then
		local payload = {
			baseUrl = state.config.base_url,
			sessionId = state.get_session_id(),
			directory = vim.fn.getcwd(),
			ensureServer = true,
			serverConfigFile = state.config.server_password_file,
			serverConfig = state.config.server_config,
			debugLogFile = state.config.debug_log_file,
		}

		run_client(state, vim.fn.json_encode(payload), function(ok, data, err)
			if not ok then
				if not opts.silent then
					vim.notify(err, vim.log.levels.ERROR, { title = "Opencode" })
					vim.notify("Server ensure failed", vim.log.levels.ERROR, { title = "Opencode" })
				end
				return
			end
		end)
		return
	end

	local payload = {
		baseUrl = state.config.base_url,
		sessionId = nil,
		sessionTitle = state.config.session_title,
		directory = vim.fn.getcwd(),
		createSession = true,
		serverConfigFile = state.config.server_password_file,
		serverConfig = state.config.server_config,
		debugLogFile = state.config.debug_log_file,
	}

	run_client(state, vim.fn.json_encode(payload), function(ok, data, err)
		if not ok then
			if not opts.silent then
				vim.notify(err, vim.log.levels.ERROR, { title = "Opencode" })
				vim.notify("Session creation failed", vim.log.levels.ERROR, { title = "Opencode" })
			end
			return
		end
		if data.sessionId then
			state.set_session_id(data.sessionId)
		end
	end)
end

return M
