local text = require("herdr-nvim-annotate-extension.text")

local M = {}

local PARTS = {
  require("herdr-nvim-annotate-extension.part.mention"),
  require("herdr-nvim-annotate-extension.part.diagnostic"),
  require("herdr-nvim-annotate-extension.part.func"),
  require("herdr-nvim-annotate-extension.part.blame"),
}

---@param target Target
---@param parts (fun(target: Target): string?)[]
---@param sink { store: fun(target: Target, text: string): integer }
---@return integer id
function M.annotate(target, parts, sink)
  local line = vim
    .iter(parts)
    :map(function(part)
      return text.one_line(part(target))
    end)
    :join(" | ")

  return sink.store(target, line)
end

---@return integer? id
---@return string? reason
function M.line()
  local target, reason = require("herdr-nvim-annotate-extension.target").current()
  if not target then
    return nil, reason
  end

  return M.annotate(target, PARTS, require("herdr-nvim-annotate-extension.sink"))
end

return M
