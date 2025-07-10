-- Auto-load the extension when telescope is available
if pcall(require, "telescope") then
  require("telescope").load_extension("mux_manager")
end