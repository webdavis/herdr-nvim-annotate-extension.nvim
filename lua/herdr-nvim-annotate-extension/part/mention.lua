---@param target Target
---@return string
return function(target)
  return ("@%s:%d"):format(vim.fn.fnamemodify(target.name, ":."), target.line)
end
