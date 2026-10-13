local M = {}

---@param s string?
---@return string?
function M.one_line(s)
  local line = vim.trim(((s or ""):gsub("%s+", " ")))
  return line ~= "" and line or nil
end

return M
