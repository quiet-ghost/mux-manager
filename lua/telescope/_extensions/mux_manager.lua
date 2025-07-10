local telescope = require("telescope")
local mux_manager = require("mux-manager")

return telescope.register_extension({
	exports = {
		mux_manager = mux_manager.sessions, -- Main entry point
		sessions = mux_manager.sessions,
		sessionizer = mux_manager.sessionizer,
	},
})
