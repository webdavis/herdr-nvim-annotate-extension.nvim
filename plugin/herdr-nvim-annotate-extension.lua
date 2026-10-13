vim.api.nvim_create_user_command("HerdrAnnotateLine", function()
  local id, reason = require("herdr-nvim-annotate-extension").line()
  if not id then
    vim.notify("herdr-nvim-annotate-extension: " .. tostring(reason), vim.log.levels.WARN)
  end
end, { desc = "Annotate the current line in herdr-nvim's store" })
