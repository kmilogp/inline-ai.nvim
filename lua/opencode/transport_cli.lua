local M = {}

local function log_debug(state, message)
	if not state.config.debug_log_file or state.config.debug_log_file == "" then
		return
	end
	pcall(vim.fn.writefile, { message }, state.config.debug_log_file, "a")
end

function M.send(state, prompt, model, cb)
	local cmd = { state.config.cli_cmd }
	if type(state.config.cli_args) == "table" then
		vim.list_extend(cmd, state.config.cli_args)
	end
	if prompt == nil then
		prompt = ""
	end
	table.insert(cmd, prompt)
	if model and model ~= "" then
		table.insert(cmd, "--model")
		table.insert(cmd, model)
	end
	local start_time = vim.loop.hrtime()
	vim.system(cmd, { text = true }, function(obj)
		vim.schedule(function()
			local elapsed_ms = math.floor((vim.loop.hrtime() - start_time) / 1000000)
			local ok = obj.code == 0
			log_debug(
				state,
				string.format(
					"%s timing.cli_transport response_ms=%d ok=%s",
					os.date("%Y-%m-%d %H:%M:%S"),
					elapsed_ms,
					ok and "true" or "false"
				)
			)
			if not ok then
				local err = (obj.stderr and obj.stderr ~= "" and obj.stderr) or obj.stdout or "unknown error"
				cb(false, nil, err)
				return
			end
			cb(true, { text = obj.stdout or "" }, nil)
		end)
	end)
end

function M.ensure_session(_, _)
	return
end

return M
