local M = {}
local telescope = require("telescope")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

-- Helper function to run tmux commands with better error handling
local function tmux_cmd(cmd)
	local full_cmd = "/usr/bin/tmux " .. cmd .. " 2>/dev/null"
	local handle = io.popen(full_cmd)
	if not handle then
		return "", 1
	end
	local result = handle:read("*a")
	local success, exit_type, exit_code = handle:close()
	return result or "", exit_code or 0
end

local function in_tmux()
	return os.getenv("TMUX") ~= nil
end

local function get_sessions()
	local output, exit_code =
		tmux_cmd("list-sessions -F '#{session_name}:#{session_attached}:#{session_windows}' 2>/dev/null || true")

	if exit_code ~= 0 or output == "" then
		return {}
	end

	local sessions = {}
	for line in output:gmatch("[^\r\n]+") do
		if line and line ~= "" then
			local parts = vim.split(line, ":")
			if #parts >= 3 then
				table.insert(sessions, {
					name = parts[1],
					attached = parts[2] == "1",
					windows_count = parts[3] or "0",
				})
			end
		end
	end

	table.sort(sessions, function(a, b)
		return a.name < b.name
	end)
	return sessions
end

local function setup_highlights()
	vim.api.nvim_set_hl(0, "TmuxActive", { fg = "#a6e3a1", bold = true }) -- bright green
	vim.api.nvim_set_hl(0, "TmuxInactive", { fg = "#6c7086" }) -- muted gray
	vim.api.nvim_set_hl(0, "TmuxName", { fg = "#cdd6f4", bold = true }) -- bright white
	vim.api.nvim_set_hl(0, "TmuxCount", { fg = "#fab387" }) -- orange
	vim.api.nvim_set_hl(0, "TmuxPath", { fg = "#94e2d5", italic = true }) -- teal
	vim.api.nvim_set_hl(0, "TmuxCommand", { fg = "#f9e2af" }) -- yellow

	-- UI elements
	vim.api.nvim_set_hl(0, "TmuxBorder", { fg = "#89b4fa" }) -- blue
	vim.api.nvim_set_hl(0, "TmuxSelected", { bg = "#313244", fg = "#cdd6f4" }) -- selection
	vim.api.nvim_set_hl(0, "TmuxDivider", { fg = "#45475a" }) -- subtle divider
	vim.api.nvim_set_hl(0, "TmuxHeader", { fg = "#f38ba8", bold = true }) -- pink header
	vim.api.nvim_set_hl(0, "TmuxKeybind", { fg = "#cba6f7" }) -- purple keybinds
	vim.api.nvim_set_hl(0, "TmuxIcon", { fg = "#89b4fa" }) -- blue icons
end

-- Create the main popup window
function M.create_popup()
	setup_highlights()

	local sessions = get_sessions()
	if #sessions == 0 then
		vim.notify("No tmux sessions found", vim.log.levels.WARN)
		return
	end

	-- Slightly larger dimensions for better content visibility
	local width = math.min(90, math.floor(vim.o.columns * 0.75))
	local height = math.min(28, math.floor(vim.o.lines * 0.7))
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local list_width = math.floor(width * 0.45)
	local preview_width = width - list_width - 3

	local main_buf = vim.api.nvim_create_buf(false, true)
	local list_buf = vim.api.nvim_create_buf(false, true)
	local preview_buf = vim.api.nvim_create_buf(false, true)

	for _, buf in ipairs({ main_buf, list_buf, preview_buf }) do
		vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
		vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
		vim.api.nvim_buf_set_option(buf, "swapfile", false)
	end

	-- Create main window
	local main_win = vim.api.nvim_open_win(main_buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
		title = " 󰙀 Tmux Session Manager ",
		title_pos = "center",
	})

	vim.api.nvim_win_set_option(main_win, "winhighlight", "Normal:Normal,FloatBorder:TmuxBorder,FloatTitle:TmuxHeader")

	local list_win = vim.api.nvim_open_win(list_buf, false, {
		relative = "win",
		win = main_win,
		width = list_width,
		height = height - 2,
		row = 1,
		col = 1,
		style = "minimal",
		border = "none",
	})
	local preview_win = vim.api.nvim_open_win(preview_buf, false, {
		relative = "win",
		win = main_win,
		width = preview_width,
		height = height - 2,
		row = 1,
		col = list_width + 2,
		style = "minimal",
		border = { "", "", "", "│", "", "", "", "" },
	})

	vim.api.nvim_win_set_option(preview_win, "winhighlight", "FloatBorder:TmuxDivider")

	local state = {
		sessions = sessions,
		current_index = 1,
		list_buf = list_buf,
		list_win = list_win,
		preview_buf = preview_buf,
		preview_win = preview_win,
		main_win = main_win,
		main_buf = main_buf,
		closed = false,
	}

	local function cleanup()
		if state.closed then
			return
		end
		state.closed = true
		for _, win in ipairs({ preview_win, list_win, main_win }) do
			if vim.api.nvim_win_is_valid(win) then
				pcall(vim.api.nvim_win_close, win, true)
			end
		end
	end

	local function render_sessions()
		if state.closed then
			return
		end

		vim.api.nvim_buf_set_option(list_buf, "modifiable", true)

		local lines = {}

		table.insert(lines, "")

		for i, session in ipairs(sessions) do
			local indicator = session.attached and "●" or "○"
			local prefix = (i == state.current_index) and " ▶ " or "   "
			local number = i <= 9 and tostring(i) or " "
			local line =
				string.format("%s%s %s %s (%s)", prefix, number, indicator, session.name, session.windows_count)
			table.insert(lines, line)
		end

		-- Add divider
		table.insert(lines, "")
		table.insert(lines, "   " .. string.rep("─", list_width - 6))
		table.insert(lines, "")

		table.insert(lines, "   󰌌 Enter/1-9: switch")
		table.insert(lines, "   󰆴 d: kill")
		table.insert(lines, "   󰑕 r: rename")
		table.insert(lines, "   󰐕 n: new")
		table.insert(lines, "   󰑐 R: refresh")
		table.insert(lines, "   󰅖 q: quit")

		vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)

		vim.api.nvim_buf_clear_namespace(list_buf, -1, 0, -1)

		for i, session in ipairs(sessions) do
			local line_idx = i + 1 -- +1 for header
			local is_current = (i == state.current_index)

			if is_current then
				vim.api.nvim_buf_add_highlight(list_buf, -1, "TmuxSelected", line_idx - 1, 0, -1)
			end

			if i <= 9 then
				vim.api.nvim_buf_add_highlight(list_buf, -1, "TmuxKeybind", line_idx - 1, 4, 5)
			end

			local hl_group = session.attached and "TmuxActive" or "TmuxInactive"
			vim.api.nvim_buf_add_highlight(list_buf, -1, hl_group, line_idx - 1, 6, 8)

			local name_start = string.find(lines[line_idx], session.name)
			if name_start then
				vim.api.nvim_buf_add_highlight(
					list_buf,
					-1,
					"TmuxName",
					line_idx - 1,
					name_start - 1,
					name_start + #session.name - 1
				)
			end

			local count_pattern = "%(%d+%)"
			local count_start, count_end = string.find(lines[line_idx], count_pattern)
			if count_start then
				vim.api.nvim_buf_add_highlight(list_buf, -1, "TmuxCount", line_idx - 1, count_start - 1, count_end)
			end
		end

		local divider_line = #sessions + 3
		vim.api.nvim_buf_add_highlight(list_buf, -1, "TmuxDivider", divider_line - 1, 0, -1)

		local keybind_start = divider_line + 2
		for i = 0, 5 do
			local line_idx = keybind_start + i
			if line_idx <= #lines then
				vim.api.nvim_buf_add_highlight(list_buf, -1, "TmuxIcon", line_idx - 1, 3, 7)
				vim.api.nvim_buf_add_highlight(list_buf, -1, "TmuxKeybind", line_idx - 1, 7, -1)
			end
		end

		vim.api.nvim_buf_set_option(list_buf, "modifiable", false)
	end

	local function update_preview()
		if state.closed then
			return
		end

		local current_session = sessions[state.current_index]
		if not current_session then
			return
		end

		vim.api.nvim_buf_set_option(preview_buf, "modifiable", true)

		local windows_output, exit_code = tmux_cmd(
			string.format(
				"list-windows -t '%s' -F '#{window_index}|#{window_name}|#{pane_current_command}|#{pane_current_path}'",
				current_session.name
			)
		)

		local lines = {
			"",
			" 󰙀 " .. current_session.name,
			"",
			" Status: " .. (current_session.attached and "󰐥 Active" or "󰒲 Inactive"),
			" Windows: " .. current_session.windows_count,
			"",
			" " .. string.rep("─", preview_width - 4),
			"",
		}

		if exit_code == 0 and windows_output ~= "" then
			table.insert(lines, " 󰖲 Windows:")
			table.insert(lines, "")
			for line in windows_output:gmatch("[^\r\n]+") do
				if line and line ~= "" then
					local parts = vim.split(line, "|")
					if #parts >= 4 then
						local window_index = parts[1]
						local window_name = parts[2]
						local command = parts[3]
						local path = parts[4]

						local display_path = path
						if path:match("^/home/[^/]+/(.+)") then
							display_path = "~/" .. path:match("^/home/[^/]+/(.+)")
						elseif path:match("^/home/[^/]+$") then
							display_path = "~"
						end

						-- Create window header
						table.insert(lines, string.format("   %s: %s", window_index, window_name))

						if
							command
							and command ~= "zsh"
							and command ~= "bash"
							and command ~= "fish"
							and command ~= "sh"
						then
							if command == "nvim" then
								local filename = display_path:match("([^/]+)$") or "file"
								table.insert(lines, "     󰈮 nvim/" .. filename)
							else
								table.insert(lines, "     󰘳 " .. command)
							end
						else
							table.insert(lines, "     󰆍 shell")
						end

						-- Add path info
						table.insert(lines, "     󰉋 " .. display_path)
						table.insert(lines, "")
					end
				end
			end
		else
			table.insert(lines, " 󰀦 No windows found")
		end

		vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)

		vim.api.nvim_buf_clear_namespace(preview_buf, -1, 0, -1)

		vim.api.nvim_buf_add_highlight(preview_buf, -1, "TmuxHeader", 1, 0, -1)

		-- Highlight status
		local status_line = 3
		vim.api.nvim_buf_add_highlight(preview_buf, -1, "TmuxIcon", status_line, 1, 3)
		if current_session.attached then
			vim.api.nvim_buf_add_highlight(preview_buf, -1, "TmuxActive", status_line, 9, -1)
		else
			vim.api.nvim_buf_add_highlight(preview_buf, -1, "TmuxInactive", status_line, 9, -1)
		end

		vim.api.nvim_buf_add_highlight(preview_buf, -1, "TmuxCount", 4, 10, -1)

		vim.api.nvim_buf_add_highlight(preview_buf, -1, "TmuxDivider", 6, 0, -1)

		vim.api.nvim_buf_add_highlight(preview_buf, -1, "TmuxHeader", 8, 0, -1)

		for i = 10, #lines do
			local line = lines[i]
			if line:match("^   %d+:") then
				vim.api.nvim_buf_add_highlight(preview_buf, -1, "TmuxName", i - 1, 0, -1)
			elseif line:match("^     󰈮") then
				vim.api.nvim_buf_add_highlight(preview_buf, -1, "TmuxCommand", i - 1, 0, -1)
			elseif line:match("^     󰘳") then
				vim.api.nvim_buf_add_highlight(preview_buf, -1, "TmuxCommand", i - 1, 0, -1)
			elseif line:match("^     󰆍") then
				vim.api.nvim_buf_add_highlight(preview_buf, -1, "TmuxInactive", i - 1, 0, -1)
			elseif line:match("^     󰉋") then
				vim.api.nvim_buf_add_highlight(preview_buf, -1, "TmuxPath", i - 1, 0, -1)
			end
		end

		vim.api.nvim_buf_set_option(preview_buf, "modifiable", false)

		vim.api.nvim_win_set_option(preview_win, "wrap", true)
		vim.api.nvim_win_set_option(preview_win, "cursorline", false)
		vim.api.nvim_win_set_option(preview_win, "number", false)
		vim.api.nvim_win_set_option(preview_win, "relativenumber", false)
	end

	local function move_up()
		if state.closed then
			return
		end
		if state.current_index > 1 then
			state.current_index = state.current_index - 1
			render_sessions()
			update_preview()
		end
	end

	local function move_down()
		if state.closed then
			return
		end
		if state.current_index < #sessions then
			state.current_index = state.current_index + 1
			render_sessions()
			update_preview()
		end
	end

	local function switch_session()
		if state.closed then
			return
		end

		local session = sessions[state.current_index]
		cleanup()

		local _, check_exit = tmux_cmd(string.format("has-session -t '%s'", session.name))
		if check_exit ~= 0 then
			vim.notify("Session '" .. session.name .. "' no longer exists", vim.log.levels.ERROR)
			return
		end

		local cmd, exit_code
		if in_tmux() then
			_, exit_code = tmux_cmd(string.format("switch-client -t '%s'", session.name))
		else
			vim.cmd(string.format("!tmux attach-session -t '%s'", session.name))
			exit_code = vim.v.shell_error
		end

		if exit_code == 0 then
			vim.notify("Switched to session: " .. session.name)
		else
			vim.notify("Failed to switch to session: " .. session.name, vim.log.levels.ERROR)
		end
	end

	local function kill_session()
		if state.closed then
			return
		end

		local session = sessions[state.current_index]
		vim.ui.input({ prompt = "Kill session '" .. session.name .. "'? (y/N): " }, function(input)
			if input and input:lower() == "y" then
				local _, exit_code = tmux_cmd(string.format("kill-session -t '%s'", session.name))
				cleanup()

				if exit_code == 0 then
					vim.notify("Killed session: " .. session.name)
				else
					vim.notify("Failed to kill session: " .. session.name, vim.log.levels.ERROR)
				end
			end
		end)
	end

	local function rename_session()
		if state.closed then
			return
		end

		local session = sessions[state.current_index]
		vim.ui.input({
			prompt = "Rename session '" .. session.name .. "' to: ",
			default = session.name,
		}, function(new_name)
			if new_name and new_name ~= "" and new_name ~= session.name then
				local _, exit_code = tmux_cmd(string.format("rename-session -t '%s' '%s'", session.name, new_name))
				cleanup()

				if exit_code == 0 then
					vim.notify("Renamed session to: " .. new_name)
				else
					vim.notify("Failed to rename session", vim.log.levels.ERROR)
				end
			end
		end)
	end

	local function get_project_dirs()
		local dirs = {}
		local mux_manager = require("mux-manager")
		local search_paths = mux_manager.config.directories

		for _, search_path in ipairs(search_paths) do
			local expanded_path = vim.fn.expand(search_path)
			local cmd = string.format("find '%s' -mindepth 1 -maxdepth 3 -type d 2>/dev/null", expanded_path)
			local handle = io.popen(cmd)
			if handle then
				for line in handle:lines() do
					if line and line ~= "" then
						table.insert(dirs, line)
					end
				end
				handle:close()
			end
		end

		return dirs
	end

	local function is_github_url(input)
		return input:match("^https://github%.com/") or input:match("^git@github%.com:")
	end

	local function clone_github_repo(url, callback)
		local repo_name = url:match("([^/]+)%.git$") or url:match("([^/]+)$")
		if not repo_name then
			vim.notify("Invalid GitHub URL", vim.log.levels.ERROR)
			return
		end

		local mux_manager = require("mux-manager")
		local repos_dir = vim.fn.expand(mux_manager.config.clone_directory)
		local target_dir = repos_dir .. "/" .. repo_name

		if vim.fn.isdirectory(target_dir) == 1 then
			vim.notify("Directory " .. target_dir .. " already exists, using existing directory")
			callback(target_dir, repo_name)
			return
		end
		vim.fn.mkdir(repos_dir, "p")
		vim.notify("Cloning " .. repo_name .. " to " .. target_dir .. "...")

		local clone_cmd = { "git", "clone", url, target_dir }
		vim.fn.jobstart(clone_cmd, {
			on_stderr = function(job_id, data, event)
				if data and #data > 0 then
					for _, line in ipairs(data) do
						if line ~= "" then
							vim.schedule(function()
								vim.notify("Git: " .. line, vim.log.levels.INFO)
							end)
						end
					end
				end
			end,
			on_exit = function(job_id, exit_code, event_type)
				vim.schedule(function()
					if exit_code == 0 then
						vim.notify("Successfully cloned " .. repo_name)
						callback(target_dir, repo_name)
					else
						vim.notify("Failed to clone repository (exit code: " .. exit_code .. ")", vim.log.levels.ERROR)
					end
				end)
			end,
		})
	end

	local function create_session_from_path(selected_path, display_name)
		local session_name = vim.fn.fnamemodify(selected_path, ":t"):gsub("%.", "_")
		local existing_output, check_exit = tmux_cmd("list-sessions -F '#{session_name}'")
		local session_exists = false
		if check_exit == 0 and existing_output then
			for line in existing_output:gmatch("[^\r\n]+") do
				if line == session_name then
					session_exists = true
					break
				end
			end
		end
		if session_exists then
			vim.notify("Session '" .. session_name .. "' already exists", vim.log.levels.WARN)
			return
		end
		local create_cmd = string.format("new-session -d -s '%s' -c '%s'", session_name, selected_path)
		local _, exit_code = tmux_cmd(create_cmd)

		if exit_code == 0 then
			local nvim_cmd = string.format("send-keys -t '%s' 'nvim' Enter", session_name)
			tmux_cmd(nvim_cmd)

			vim.defer_fn(function()
				local telescope_cmd = string.format("send-keys -t '%s' ':Telescope find_files' Enter", session_name)
				tmux_cmd(telescope_cmd)
			end, 500)

			cleanup()

			vim.notify("Created session: " .. session_name .. " in " .. display_name)

			vim.defer_fn(function()
				if in_tmux() then
					tmux_cmd(string.format("switch-client -t '%s'", session_name))
				end
			end, 100)
		else
			vim.notify("Failed to create session: " .. session_name, vim.log.levels.ERROR)
		end
	end

	local function new_session()
		if state.closed then
			return
		end

		local project_dirs = get_project_dirs()
		local items = {}

		for _, dir in ipairs(project_dirs) do
			local display_name = dir:gsub("^" .. vim.fn.expand("~"), "~")
			table.insert(items, {
				path = dir,
				display = display_name,
			})
		end

		cleanup()

		pickers
			.new({}, {
				prompt_title = "Search Projects or Paste GitHub URL",
				finder = finders.new_table({
					results = items,
					entry_maker = function(entry)
						return {
							value = entry,
							display = entry.display,
							ordinal = entry.display,
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr, map)
					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						local current_line = action_state.get_current_line()

						actions.close(prompt_bufnr)

						if current_line and is_github_url(current_line) then
						clone_github_repo(current_line, function(target_dir, repo_name)
							local mux_manager = require("mux-manager")
							local display_path = mux_manager.config.clone_directory:gsub("^" .. vim.fn.expand("~"), "~") .. "/" .. repo_name
							create_session_from_path(target_dir, display_path)
						end)						elseif selection then
							create_session_from_path(selection.value.path, selection.value.display)
						end
					end)

					return true
				end,
			})
			:find()
	end

	local function refresh_sessions()
		if state.closed then
			return
		end

		local new_sessions = get_sessions()
		if #new_sessions == 0 then
			vim.notify("No tmux sessions found", vim.log.levels.WARN)
			cleanup()
			return
		end

		state.sessions = new_sessions
		sessions = new_sessions

		if state.current_index > #sessions then
			state.current_index = #sessions
		end

		render_sessions()
		update_preview()
	end

	-- Set up keymaps
	local keymaps = {
		["<CR>"] = switch_session,
		["<Esc>"] = cleanup,
		["q"] = cleanup,
		["j"] = move_down,
		["k"] = move_up,
		["<Down>"] = move_down,
		["<Up>"] = move_up,
		["d"] = kill_session,
		["r"] = rename_session,
		["n"] = new_session,
		["R"] = refresh_sessions,
	}

	for key, func in pairs(keymaps) do
		vim.keymap.set("n", key, func, { buffer = list_buf, silent = true })
	end
	for i = 1, 9 do
		vim.keymap.set("n", tostring(i), function()
			if i <= #sessions then
				state.current_index = i
				switch_session()
			end
		end, { buffer = list_buf, silent = true })
	end

	vim.api.nvim_create_autocmd("BufDelete", {
		buffer = list_buf,
		callback = cleanup,
		once = true,
	})

	render_sessions()
	update_preview()

	vim.api.nvim_set_current_win(list_win)

	return state
end

return M
