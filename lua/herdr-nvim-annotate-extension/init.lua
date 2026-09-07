-- herdr-nvim-annotate-extension: the line annotator that feeds herdr-nvim.
--
-- `line()` writes down what you would otherwise retype at an agent: where the
-- line is, what the language server says about it, which function it sits in,
-- and which commit last touched it.
--
-- Delivery is not this plugin's job. The text goes into herdr-nvim's own
-- annotation store, which already ships the keys that paste or send pending
-- comments, so nothing here types into an agent and there is no state to race.
--
-- herdr-nvim is required INSIDE the function that reaches it, so requiring this
-- module costs nothing and pulls no plugin in behind it.

local M = {}

local compose = require("herdr-nvim-annotate-extension.compose")
local git = require("herdr-nvim-annotate-extension.git")

-- What goes between the parts of a STORED annotation. One line, not four,
-- because herdr-nvim's comment listing builds one buffer line per comment out
-- of the comment's own text (`ui.lua:89`, `ui.lua:147` at the installed
-- commit 41c30f5) and `nvim_buf_set_lines` raises
-- `'replacement string' item contains newlines` on anything multi-line. Every
-- annotation carrying two parts therefore broke `<leader>Al` outright.
--
-- It lives on this module rather than on the composer because the reason for it
-- is the store's, not the text's: `compose_text` still joins with a newline by
-- default and takes whichever separator it is handed. Set it to "\n" once
-- herdr-nvim can list a multi-line comment. It is exported so the tests pin it,
-- and so a config that wants a different separator can set it.
M.PART_SEPARATOR = " | "

-- ╭──────────────────╮
-- │  The editor edge │
-- ╰──────────────────╯

local function diagnostic_part(bufnr, line)
  return compose.diagnostic_line(vim.diagnostic.get(bufnr, { lnum = line - 1 })[1])
end

local function function_part(bufnr, line, column)
  -- The CURSOR's column, not zero. Column zero of a nested declaration line
  -- sits outside the function being declared, so it named the function around
  -- it instead; column zero of an indented `def` or `func` line is leading
  -- whitespace, which named no function at all.
  --
  -- `get_node` returns nil rather than raising when no parser is attached
  -- (verified in the 0.12 runtime: `get_parser` reports a message, it does not
  -- error), so an unparsed buffer simply contributes no function part.
  local node = compose.enclosing_function(vim.treesitter.get_node({ bufnr = bufnr, pos = { line - 1, column } }))
  if not node then
    return nil
  end

  -- An anonymous function has no `name` field, and its node type alone says
  -- nothing the reader cannot already see, so it contributes no part either.
  local name = node:field("name")[1]
  if not name then
    return nil
  end

  -- A declaration is free to wrap, so the `name` field can span lines.
  return "function " .. compose.one_line(vim.treesitter.get_node_text(name, bufnr))
end

local function blame_part(name, line)
  -- Both calls return `nil, message` on failure (a file outside a repository,
  -- a line not committed yet); the message is the keymap layer's to report,
  -- and here a line the annotator cannot blame is a part it does not write.
  local sha = git.blame_sha({ file = name, line = line })
  if not sha then
    return nil
  end

  -- Bound to one value on purpose: `head_commit` answers `(commit, err)`, and
  -- passing the call straight through would spread its error message into
  -- `blame_line`'s next parameter.
  local commit = git.head_commit(name)

  return compose.blame_line(sha, commit)
end

-- ╭──────╮
-- │  API │
-- ╰──────╯

---Store `parts` as one annotation on `line` of `bufnr`, and decorate it.
---
---The sink, and the one place that knows what `herdr-nvim` can render: it
---flattens the parts onto one line on the way in. The id the store hands back
---is what puts the annotation's mark in the buffer, so it goes straight to
---`ui.decorate`; an annotation stored and not decorated is invisible until
---something else redraws.
---@param bufnr integer
---@param line integer
---@param parts { mention: string?, diagnostic: string?, func: string?, blame: string? }
---@return integer id the new comment's id
function M.store(bufnr, line, parts)
  local normalized = vim.tbl_map(compose.one_line, parts or {})
  local text = compose.compose_text(normalized, M.PART_SEPARATOR)

  local id = require("herdr-nvim.comments").add(bufnr, line, line, text)
  require("herdr-nvim.ui").decorate(id)

  return id
end

---Annotate the cursor's line in `herdr-nvim`'s annotation store.
---@return integer? id the new comment's id, or nil when the buffer cannot be annotated
---@return string? reason why not
function M.line()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line, column = cursor[1], cursor[2]
  local name = vim.api.nvim_buf_get_name(bufnr)

  local ok, reason = compose.annotatable(name, vim.bo[bufnr].buftype)
  if not ok then
    return nil, reason
  end

  local file = vim.fn.fnamemodify(name, ":.")

  return M.store(bufnr, line, {
    mention = ("@%s:%d"):format(file, line),
    diagnostic = diagnostic_part(bufnr, line),
    func = function_part(bufnr, line, column),
    blame = blame_part(name, line),
  })
end

return M
