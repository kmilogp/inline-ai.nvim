local M = {}

function M.list()
	return {
		{
			title = "Extract Function",
			prompt = "Refactor the current code by extracting it into a function. If the code is inside a class, extract it as a private method; otherwise extract it as a regular function. Keep behavior unchanged and update call sites as needed.",
			profile = "fast",
			description = "Extract logic into function/method",
		},
		{
			title = "Quick Refactor",
			prompt = "Refactor the current file for readability while keeping behavior unchanged.",
			profile = "fast",
			description = "Safe cleanup pass",
		},
		{
			title = "Fix Diagnostics",
			prompt = "Fix current file diagnostics with minimal, safe changes.",
			profile = "fast",
			description = "Address errors and warnings",
		},
		{
			title = "Add Tests",
			prompt = "Add focused tests for the current change and edge cases.",
			profile = "deep",
			description = "Generate robust test coverage",
		},
	}
end

return M
