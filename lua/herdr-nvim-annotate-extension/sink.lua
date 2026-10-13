local comments = require("herdr-nvim.comments")
local ui = require("herdr-nvim.ui")

local M = {}

---@param target Target
---@param text string
---@return integer id
function M.store(target, text)
  local id = comments.add(target.bufnr, target.line, target.line, text)
  ui.decorate(id)

  return id
end

return M
