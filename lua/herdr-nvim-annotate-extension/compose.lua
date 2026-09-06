-- The annotator's pure core: text in, text out. Nothing here reads a buffer,
-- the diagnostic store, a treesitter tree or git, so every rule below is
-- testable with plain data and holds with no plugin installed.
--
-- The separator is deliberately NOT decided here. Joining with something other
-- than a newline is a limit of the store the annotation is written to, so the
-- caller states it and `herdr-nvim-annotate-extension.init` is the caller that knows.

local M = {}

-- Every grammar spells its function node differently, so the rule is a SUFFIX
-- match over the six spellings that cover the languages this plugin handles.
-- A `find` on "function" would match `function_call` and `parameters` and walk
-- no further, reporting the call around the cursor as its enclosing function.
-- The match is anchored at the END for the same reason: `function_definition_call`
-- contains a listed spelling without being one.
--
-- Measured by walking a sample file per language under the installed grammars.
-- `(name)` is what the function part reads; a node with no name field
-- contributes no function part at all.
--
--   lua         function_declaration (name), function_definition (no name)
--   python      function_definition (name)
--   bash        function_definition (name)
--   rust        function_item (name)
--   go          function_declaration (name), method_declaration (name)
--   swift       function_declaration (name)
--   typescript  function_declaration, function_expression, method_definition (all name),
--               arrow_function (no name, and no suffix here)
local FUNCTION_NODE_SUFFIXES = {
  "function_definition",
  "function_declaration",
  "method_definition",
  "function_item",
  "method_declaration",
  "function_expression",
}

-- The order the parts appear in, stated once. `pairs` over the parts table
-- would order them by whatever the hash walk returned that run.
local PART_ORDER = { "mention", "diagnostic", "func", "blame" }

-- ╭──────╮
-- │  API │
-- ╰──────╯

---Remove surrounding whitespace from `s`.
---
---The outer parentheses are load-bearing: they drop `gsub`'s substitution
---count, which every caller in tail position would otherwise return as a second
---value of its own.
---@param s string?
---@return string
function M.trim(s)
  return ((s or ""):gsub("^%s*(.-)%s*$", "%1"))
end

---Collapse `text` onto one line.
---
---Every part of an annotation is one line: both a language server message and a
---treesitter node's text can arrive spanning several, so both go through here.
---@param text string
---@return string
function M.one_line(text)
  return M.trim((text:gsub("%s+", " ")))
end

---Join the parts into one annotation, in a fixed order.
---
---A missing part contributes nothing at all: an annotation whose diagnostic was
---absent must not carry the gap where it would have been.
---@param parts { mention: string?, diagnostic: string?, func: string?, blame: string? }
---@param separator string? what goes between the parts; a newline by default
---@return string
function M.compose_text(parts, separator)
  parts = parts or {}

  local kept = {}
  for _, key in ipairs(PART_ORDER) do
    local part = parts[key]
    -- An empty string is a missing part too: a diagnostic message that trimmed
    -- to nothing arrives as "" rather than nil.
    if part and part ~= "" then
      kept[#kept + 1] = part
    end
  end

  return table.concat(kept, separator or "\n")
end

---The innermost function-shaped node at or above `node`, or nil outside one.
---@param node TSNode? the node under the cursor
---@return TSNode?
function M.enclosing_function(node)
  while node do
    local node_type = node:type()
    for _, suffix in ipairs(FUNCTION_NODE_SUFFIXES) do
      if vim.endswith(node_type, suffix) then
        return node
      end
    end
    node = node:parent()
  end

  return nil
end

---The blame part: the line's commit, named when the repository can name it.
---
---`git.head_commit` describes HEAD and nothing else, so its summary belongs to
---the blamed line only when the blame SHA *is* HEAD. Attached any other time it
---would caption the line with an unrelated commit's message.
---@param sha string? the blame SHA, or nil when the line has none
---@param commit { hash: string, summary: string? }? HEAD, as `git.head_commit` returns it
---@return string?
function M.blame_line(sha, commit)
  if not sha then
    return nil
  end

  local short = sha:sub(1, 7)

  if commit and commit.summary and commit.hash and vim.startswith(sha, commit.hash) then
    return ("blame %s %s"):format(short, commit.summary)
  end

  return "blame " .. short
end

-- A buffer name that opens with a URI scheme belongs to a plugin, not to the
-- filesystem. MEASURED: an Oil directory buffer and a Fugitive revision buffer
-- both carry an EMPTY `buftype`, so the buftype test below does not reach
-- them; their names are what gives them away. The scheme is anchored at the
-- start, so a legal path holding `://` further along stays a path.
local URI_NAME = "^%a[%w+.-]*://"

---Whether this buffer can produce a mention an agent could act on.
---
---A named file that has never been written is fine: it is a real path with
---real lines. The three refusals are a buffer with no name, which would be
---mentioned as `@:1`; a buffer with any `buftype`, which is a scratch buffer,
---a terminal, a quickfix list or a help window rather than a file; and a
---buffer named by a URI, whose name is not a path an agent can open.
---@param name string the buffer name, as `nvim_buf_get_name` returns it
---@param buftype string the buffer's `buftype`
---@return boolean annotatable
---@return string? reason why not, when it is not
function M.annotatable(name, buftype)
  if name == "" then
    return false, "this buffer has no file name"
  end

  if buftype ~= "" then
    return false, ("this is a %s buffer, not a file"):format(buftype)
  end

  if name:match(URI_NAME) then
    return false, ("this buffer is named by a URI, not a path: %s"):format(name)
  end

  return true
end

---The diagnostic part: the severity and the message, on one line.
---
---A message that trims to nothing yields no part at all. Formatting it anyway
---would contribute the bare severity label, `ERROR: `, which `compose_text`
---reads as a real part because it is not empty.
---@param diagnostic { severity: integer, message: string }? as `vim.diagnostic.get` returns it
---@return string?
function M.diagnostic_line(diagnostic)
  if not diagnostic then
    return nil
  end

  local message = M.one_line(diagnostic.message)
  if message == "" then
    return nil
  end

  return ("%s: %s"):format(vim.diagnostic.severity[diagnostic.severity], message)
end

return M
