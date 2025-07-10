local popup = require("mux-manager.popup")

local M = {}

-- Default configuration
local default_config = {
	directories = { "~/dev", "~/personal" },
	max_depth = 3,
	min_depth = 1,
	clone_directory = "~/dev/repos",
}

-- User configuration
M.config = default_config

-- Setup function for user configuration
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", default_config, opts or {})
end

-- Helper function to run tmux commands
local function tmux_cmd(cmd)
	local handle = io.popen("/usr/bin/tmux " .. cmd .. " 2>/dev/null")
	if not handle then
		return ""
	end
	local result = handle:read("*a")
	handle:close()
	return result or ""
end

-- Main session manager function (uses custom popup)
function M.sessions()
	popup.create_popup()
end

-- Project sessionizer (still uses telescope for now)
function M.sessionizer()
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	local directories_str = table.concat(M.config.directories, " ")
	local dirs_output = tmux_cmd("run-shell 'find " .. directories_str .. " -mindepth " .. M.config.min_depth .. " -maxdepth " .. M.config.max_depth .. " -type d 2>/dev/null'")

	if dirs_output == "" then
		print("No directories found")
		return
	end

	local directories = {}
	for dir in dirs_output:gmatch("[^\r\n]+") do
		if dir and dir ~= "" then
			local display_name = vim.fn.fnamemodify(dir, ":t") .. " (" .. vim.fn.fnamemodify(dir, ":h") .. ")"
			table.insert(directories, {
				path = dir,
				display = display_name,
				name = vim.fn.fnamemodify(dir, ":t"),
			})
		end
	end

	if #directories == 0 then
		print("No directories found")
		return
	end

	pickers
		.new({}, {
			prompt_title = "tmux sessionizer",
			layout_strategy = "horizontal",
			layout_config = {
				width = 0.95,
				height = 0.85,
				horizontal = {
					preview_width = 0.75,
					prompt_position = "bottom",
				},
			},
			finder = finders.new_table({
				results = directories,
				entry_maker = function(entry)
					return {
						value = entry.path,
						display = entry.display,
						ordinal = entry.name,
						name = entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				title = "Directory Contents",
				define_preview = function(self, entry, status)
					local dir_path = entry.value
					local files_output = vim.fn.system("ls -la '" .. dir_path .. "' 2>/dev/null")

					local lines = { "Directory: " .. dir_path, "" }
					if files_output and files_output ~= "" then
						for line in files_output:gmatch("[^\r\n]+") do
							table.insert(lines, line)
						end
					else
						table.insert(lines, "Directory is empty or inaccessible")
					end

					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)

					local dir_path = selection.value
					local session_name = selection.name:gsub("%.", "_")

					-- Check if session already exists
					local existing = tmux_cmd("has-session -t '" .. session_name .. "'")
					if vim.v.shell_error == 0 then
						-- Session exists, switch to it
						os.execute("/usr/bin/tmux switch-client -t '" .. session_name .. "'")
						print("Switched to existing session: " .. session_name)
					else
						-- Create new session
						os.execute("/usr/bin/tmux new-session -d -s '" .. session_name .. "' -c '" .. dir_path .. "'")
						os.execute("/usr/bin/tmux switch-client -t '" .. session_name .. "'")
						print("Created and switched to session: " .. session_name)
					end
				end)

				return true
			end,
		})
		:find()
end

return M
