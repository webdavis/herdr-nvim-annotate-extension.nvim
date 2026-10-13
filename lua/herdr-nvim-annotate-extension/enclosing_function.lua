local FUNCTION_NODE_SUFFIXES = {
  "function_definition",
  "function_declaration",
  "method_definition",
  "function_item",
  "method_declaration",
  "function_expression",
}

---@param node TSNode?
---@return TSNode?
return function(node)
  while node do
    local node_type = node:type()
    for _, suffix in ipairs(FUNCTION_NODE_SUFFIXES) do
      if vim.endswith(node_type, suffix) then
        return node
      end
    end
    node = node:parent()
  end

  return nil
end
