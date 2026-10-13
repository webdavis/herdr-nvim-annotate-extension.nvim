local func = require("herdr-nvim-annotate-extension.part.func")

local function part_at(lines, line, column)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = "lua"
  vim.treesitter.get_parser(bufnr, "lua"):parse()
  local ok, part = pcall(func, { bufnr = bufnr, name = "", line = line, column = column })
  vim.api.nvim_buf_delete(bufnr, { force = true })
  assert(ok, part)
  return part
end

return {
  ["names a function declared across lines on one line"] = function()
    local part = part_at({ "local foo = {}", "function foo", "  .bar()", "  return 1", "end" }, 4, 2)
    assert(part == "function foo .bar", "function part " .. vim.inspect(part))
  end,

  ["reads the function at the cursor's column, not at the start of its line"] = function()
    local part = part_at({ "function outer()", "  local function inner()", "    return 1", "  end", "end" }, 2, 18)
    assert(part == "function inner", "function part " .. vim.inspect(part))
  end,
}
