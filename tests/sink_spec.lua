local comments = require("herdr-nvim.comments")
local sink = require("herdr-nvim-annotate-extension.sink")
local ui = require("herdr-nvim.ui")

return {
  ["hands the store one line and decorates the id it gave back"] = function()
    local id = sink.store({ bufnr = 7, name = "/tmp/init.lua", line = 42, column = 0 }, "@init.lua:42 | blame a1b2c3d")
    local added = comments.added[id]
    assert(
      vim.deep_equal(added, { bufnr = 7, start_line = 42, end_line = 42, text = "@init.lua:42 | blame a1b2c3d" }),
      "stored " .. vim.inspect(added)
    )
    assert(ui.decorated[#ui.decorated] == id, "decorated " .. vim.inspect(ui.decorated))
  end,
}
