local enclosing_function = require("herdr-nvim-annotate-extension.enclosing_function")

local function chain(types)
  local node
  for index = #types, 1, -1 do
    local parent = node
    node = {
      _type = types[index],
      type = function(self)
        return self._type
      end,
      parent = function()
        return parent
      end,
    }
  end
  return node
end

local function found_type(types)
  local found = enclosing_function(chain(types))
  return found and found:type()
end

return {
  ["walks up to the enclosing function node"] = function()
    local found = found_type({ "identifier", "arguments", "function_declaration", "chunk" })
    assert(found == "function_declaration", "found " .. tostring(found))
  end,

  ["reads the cursor node itself as the enclosing function"] = function()
    local found = found_type({ "function_definition", "chunk" })
    assert(found == "function_definition", "found " .. tostring(found))
  end,

  ["stops at the innermost function-shaped ancestor"] = function()
    local found = found_type({ "identifier", "method_definition", "class_definition", "function_declaration" })
    assert(found == "method_definition", "found " .. tostring(found))
  end,

  ["finds no function outside one"] = function()
    assert(enclosing_function(chain({ "identifier", "table_constructor", "chunk" })) == nil)
    assert(enclosing_function(nil) == nil)
  end,

  ["does not read a merely function-adjacent node as a function"] = function()
    local found = found_type({ "identifier", "function_call", "parameters", "function_definition" })
    assert(found == "function_definition", "found " .. tostring(found))
  end,

  ["covers the function node of every language it handles"] = function()
    for _, node_type in ipairs({
      "function_definition",
      "function_declaration",
      "method_definition",
      "function_item",
      "method_declaration",
      "function_expression",
    }) do
      assert(found_type({ "identifier", node_type }) == node_type, node_type .. " is not read as a function")
    end
  end,

  ["reads a suffix only at the end of the node type"] = function()
    local found = found_type({ "identifier", "function_definition_call", "function_declaration" })
    assert(found == "function_declaration", "found " .. tostring(found))
  end,
}
