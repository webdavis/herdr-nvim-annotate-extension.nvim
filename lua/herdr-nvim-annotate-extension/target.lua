---@class Target
---@field bufnr integer
---@field name string
---@field line integer
---@field column integer

local M = {}

local URI_NAME = "^%a[%w+.-]*://"

---@param name string
---@param buftype string
---@return boolean annotatable
---@return string? reason
function M.annotatable(name, buftype)
  if name == "" then
    return false, "this buffer has no file name"
  end

  if buftype ~= "" then
    return false, ("this buffer is not a file on disk (buftype=%s)"):format(buftype)
  end

  if name:match(URI_NAME) then
    return false, ("this buffer is named by a URI, not a path: %s"):format(name)
  end

  return true
end

---@return Target? target
---@return string? reason
function M.current()
  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)

  local ok, reason = M.annotatable(name, vim.bo[bufnr].buftype)
  if not ok then
    return nil, reason
  end

  local cursor = vim.api.nvim_win_get_cursor(0)

  return { bufnr = bufnr, name = name, line = cursor[1], column = cursor[2] }
end

return M
