local M = { added = {} }

function M.add(bufnr, start_line, end_line, text)
  table.insert(M.added, { bufnr = bufnr, start_line = start_line, end_line = end_line, text = text })

  return #M.added
end

return M
