local M = { decorated = {} }

function M.decorate(id)
  table.insert(M.decorated, id)
end

return M
