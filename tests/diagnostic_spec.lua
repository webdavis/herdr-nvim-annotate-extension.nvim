local diagnostic = require("herdr-nvim-annotate-extension.part.diagnostic")

local NAMESPACE = vim.api.nvim_create_namespace("diagnostic-part-spec")

local function part_for(diagnostics)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = y" })
  vim.diagnostic.set(NAMESPACE, bufnr, diagnostics)
  local ok, part = pcall(diagnostic, { bufnr = bufnr, name = "", line = 1, column = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
  assert(ok, part)
  return part
end

local function one(severity, message)
  return { { lnum = 0, col = 0, severity = vim.diagnostic.severity[severity], message = message } }
end

return {
  ["names the severity beside the diagnostic message"] = function()
    local part = part_for(one("WARN", "unused local"))
    assert(part == "WARN: unused local", "diagnostic part " .. vim.inspect(part))
  end,

  ["collapses a multi-line diagnostic message onto one line"] = function()
    local part = part_for(one("ERROR", "expected type\n  found string"))
    assert(part == "ERROR: expected type found string", "diagnostic part " .. vim.inspect(part))
  end,

  ["has no diagnostic part when the message is only whitespace"] = function()
    assert(part_for(one("ERROR", "   ")) == nil)
    assert(part_for(one("ERROR", "")) == nil)
  end,

  ["has no diagnostic part without a diagnostic"] = function()
    assert(part_for({}) == nil)
  end,
}
