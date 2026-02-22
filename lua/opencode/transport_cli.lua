local M = {}
-- Transport implementation that proxies prompts through the configured CLI helper.

local function log_debug(state, message)
	-- Skip logging when no debug path is configured.
	if not state.config.debug_log_file or state.config.debug_log_file == "" then
		return
	end
	pcall(vim.fn.writefile, { message }, state.config.debug_log_file, "a")
end

function M.send(state, prompt, model, cb)
	-- Assemble the CLI invocation, appending any configured extra args.
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
	-- Execute the CLI asynchronously and record timing for diagnostics.
	vim.system(cmd, { text = true }, function(obj)
		vim.schedule(function()
			local ok = obj.code == 0

			if not ok then
				-- Translate CLI failures into callback errors for callers.
				local err = (obj.stderr and obj.stderr ~= "" and obj.stderr) or obj.stdout or "unknown error"
				cb(false, nil, err)
				return
			end
			-- Return trimmed CLI stdout to the caller when exit code 0.
			cb(true, { text = obj.stdout or "" }, nil)
		end)
	end)
end

return M
