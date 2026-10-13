local text = require("herdr-nvim-annotate-extension.text")

---@param target Target
---@return string?
return function(target)
  local diagnostic = vim.diagnostic.get(target.bufnr, { lnum = target.line - 1 })[1]
  local message = diagnostic and text.one_line(diagnostic.message)
  if not message then
    return nil
  end

  return ("%s: %s"):format(vim.diagnostic.severity[diagnostic.severity], message)
end
