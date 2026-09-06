-- `:HerdrAnnotateLine`, the entry point to bind a key to.
--
-- `line()` answers `nil, reason` for a buffer it cannot annotate and notifies
-- nothing itself, so that a config with its own error boundary can decide how a
-- refusal is reported. This command is the default: it says why, once, rather
-- than doing nothing visible.

vim.api.nvim_create_user_command("HerdrAnnotateLine", function()
  local id, reason = require("herdr-nvim-annotate-extension").line()
  if not id then
    vim.notify("herdr-nvim-annotate-extension: " .. tostring(reason), vim.log.levels.WARN)
  end
end, { desc = "Annotate the current line in herdr-nvim's store" })
