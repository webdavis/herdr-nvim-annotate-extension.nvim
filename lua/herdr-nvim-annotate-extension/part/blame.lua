local git = require("herdr-nvim-annotate-extension.git")

local LINE_SEPARATOR = { unix = "\n", dos = "\r\n", mac = "\r" }

local function unsaved_contents(bufnr)
  if not vim.bo[bufnr].modified then
    return nil
  end

  local separator = vim.bo[bufnr].binary and "\n" or LINE_SEPARATOR[vim.bo[bufnr].fileformat]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  if separator == "\r" then
    lines = vim.tbl_map(function(line)
      return (line:gsub("\r", "\n"))
    end, lines)
  end

  local text = table.concat(lines, separator)

  return vim.bo[bufnr].endofline and text .. separator or text
end

---@param target Target
---@param run? fun(opts: { cmd: string[], stdin: string?, cwd: string? }): integer, string
---@return string?
return function(target, run)
  local commit = git.blame({ file = target.name, line = target.line, contents = unsaved_contents(target.bufnr) }, run)
  if not commit then
    return nil
  end

  local short = commit.sha:sub(1, 7)

  return commit.summary and ("blame %s %s"):format(short, commit.summary) or "blame " .. short
end
