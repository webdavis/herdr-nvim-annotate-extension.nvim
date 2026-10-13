local enclosing_function = require("herdr-nvim-annotate-extension.enclosing_function")
local text = require("herdr-nvim-annotate-extension.text")

---@param target Target
---@return string?
return function(target)
  local cursor = vim.treesitter.get_node({ bufnr = target.bufnr, pos = { target.line - 1, target.column } })
  local node = enclosing_function(cursor)
  local name = node and node:field("name")[1]
  if not name then
    return nil
  end

  return "function " .. text.one_line(vim.treesitter.get_node_text(name, target.bufnr))
end
