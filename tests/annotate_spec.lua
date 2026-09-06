-- The pure composer, and the sink that hands its text to herdr-nvim.
--
-- `annotate.line()` reads the cursor, the diagnostic store, a treesitter tree
-- and git. What is pinned here is the composer, the node-type filter, the blame
-- formatter and the sink, each of which takes plain data.

local annotate = require("herdr-nvim-annotate-extension")
local compose = require("herdr-nvim-annotate-extension.compose")
local git = require("herdr-nvim-annotate-extension.git")

-- The two `herdr-nvim` modules the sink reaches, replaced by fakes that record
-- what they were handed. `--clean` puts `herdr-nvim` on no runtimepath, so
-- `package.loaded` is where the substitution has to happen.
--
-- Returns what the store was given, what was decorated, and `body`'s own
-- `pcall` result. The raise is reported by the CALLER rather than here, so a
-- caller that also has a buffer to delete still gets to clean up first.
local function with_fake_store(body)
  local real_comments = package.loaded["herdr-nvim.comments"]
  local real_ui = package.loaded["herdr-nvim.ui"]

  local added, decorated
  package.loaded["herdr-nvim.comments"] = {
    add = function(bufnr, start_line, end_line, text)
      added = { bufnr = bufnr, start_line = start_line, end_line = end_line, text = text }
      return 4242
    end,
  }
  package.loaded["herdr-nvim.ui"] = {
    decorate = function(id)
      decorated = id
    end,
  }

  local ok, result, reason = pcall(body)

  package.loaded["herdr-nvim.comments"] = real_comments
  package.loaded["herdr-nvim.ui"] = real_ui

  return added, decorated, ok, result, reason
end

-- `annotate.line()` reaches four things. Two of them, the diagnostic store and
-- treesitter, are core and real here: nvim ships a Lua parser
-- (`lib/nvim/parser/lua.so`), which attaches under `--clean`. The other two are
-- substituted because they are not what these cases are about: git would shell
-- out, and `herdr-nvim` is a plugin no `--clean` run has on its runtimepath.
--
-- Returns the text the annotator handed to the store.
local function annotated(lines, cursor)
  local real_runner = git.runner
  git.runner = function()
    return 128, "fatal: not a git repository"
  end

  local previous = vim.api.nvim_get_current_buf()
  -- NOT a scratch buffer: `nvim_create_buf(_, true)` sets `buftype = nofile`,
  -- which the annotator refuses. A name is required too (an unnamed buffer is
  -- refused) and has to be a real path, because the git edge asks for its
  -- directory.
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".lua")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = "lua"
  vim.api.nvim_set_current_buf(bufnr)
  vim.treesitter.get_parser(bufnr, "lua"):parse()
  vim.api.nvim_win_set_cursor(0, cursor)

  local added, _, ok, result, reason = with_fake_store(annotate.line)

  vim.api.nvim_set_current_buf(previous)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  git.runner = real_runner

  assert(ok, result)
  assert(result, "the annotator refused the buffer: " .. tostring(reason))
  return added.text
end

-- Row 2 is `  local function inner()`; column 18 is inside `inner`, column 0 is
-- outside it and inside `outer`.
local NESTED = {
  "function outer()",
  "  local function inner()",
  "    return 1",
  "  end",
  "end",
}

-- A treesitter node stands in for the real one through the two methods the
-- filter calls. The chain is built innermost-first, so `chain({"a","b"})`
-- returns the "a" node whose parent is the "b" node.
local function chain(types)
  local node
  for index = #types, 1, -1 do
    local parent = node
    node = {
      _type = types[index],
      type = function(self)
        return self._type
      end,
      parent = function()
        return parent
      end,
    }
  end
  return node
end

return {
  ["joins every part one per line"] = function()
    local text = compose.compose_text({
      mention = "@lua/herdr-nvim-annotate-extension/init.lua:42",
      diagnostic = "ERROR: undefined variable",
      func = "function compose_text",
      blame = "blame a1b2c3d add the annotator",
    })
    assert(
      text
        == "@lua/herdr-nvim-annotate-extension/init.lua:42\n"
          .. "ERROR: undefined variable\n"
          .. "function compose_text\n"
          .. "blame a1b2c3d add the annotator",
      "composed " .. vim.inspect(text)
    )
  end,

  ["returns just the mention when it is the only part"] = function()
    local text = compose.compose_text({ mention = "@init.lua:1" })
    assert(text == "@init.lua:1", "composed " .. vim.inspect(text))
  end,

  ["leaves no blank line where a part is nil"] = function()
    -- The diagnostic is the missing middle part: a composer that emitted "" for
    -- it would still hold four lines, and the annotation would carry a gap.
    local text = compose.compose_text({
      mention = "@init.lua:1",
      func = "function setup",
      blame = "blame a1b2c3d",
    })
    assert(text == "@init.lua:1\nfunction setup\nblame a1b2c3d", "composed " .. vim.inspect(text))
    assert(not text:find("\n\n", 1, true), "blank line in " .. vim.inspect(text))
  end,

  ["orders the parts mention, diagnostic, function, blame"] = function()
    -- Each value names its own role, so a composer that walked the table with
    -- `pairs` (unordered) or reversed the sequence reports which order it used.
    local text = compose.compose_text({
      blame = "fourth",
      func = "third",
      diagnostic = "second",
      mention = "first",
    })
    assert(text == "first\nsecond\nthird\nfourth", "composed " .. vim.inspect(text))
  end,

  ["joins with the separator it was given"] = function()
    -- The stored text is single-line, because herdr-nvim's comment listing
    -- cannot render a newline; the pure join still takes whichever separator
    -- the caller wants, so it reverts by changing one argument.
    local text = compose.compose_text({
      mention = "@init.lua:1",
      diagnostic = "ERROR: undefined variable",
      func = "function setup",
      blame = "blame a1b2c3d",
    }, " | ")
    assert(
      text == "@init.lua:1 | ERROR: undefined variable | function setup | blame a1b2c3d",
      "composed " .. vim.inspect(text)
    )
  end,

  ["stores its parts on one line, separated by a pipe"] = function()
    -- The stored shape is not an implementation detail: herdr-nvim's listing
    -- cannot render a newline, and the parts still have to be told apart by
    -- whoever reads the annotation.
    assert(annotate.PART_SEPARATOR == " | ", "separator is " .. vim.inspect(annotate.PART_SEPARATOR))
    local text = compose.compose_text({ mention = "@init.lua:1", blame = "blame a1b2c3d" }, annotate.PART_SEPARATOR)
    assert(not text:find("\n", 1, true), "stored text holds a newline: " .. vim.inspect(text))
    assert(text == "@init.lua:1 | blame a1b2c3d", "composed " .. vim.inspect(text))
  end,

  ["separates by newline when it was given no separator"] = function()
    local text = compose.compose_text({ mention = "@init.lua:1", blame = "blame a1b2c3d" })
    assert(text == "@init.lua:1\nblame a1b2c3d", "composed " .. vim.inspect(text))
  end,

  ["never doubles the separator around a missing part"] = function()
    local text = compose.compose_text({ mention = "@init.lua:1", blame = "blame a1b2c3d" }, " | ")
    assert(text == "@init.lua:1 | blame a1b2c3d", "composed " .. vim.inspect(text))
  end,

  ["treats an empty part as no part"] = function()
    -- `git.head_commit` returns a normalized summary, but a diagnostic message
    -- trimmed to nothing arrives as "" rather than nil.
    local text = compose.compose_text({ mention = "@init.lua:1", diagnostic = "", blame = "blame a1b2c3d" })
    assert(text == "@init.lua:1\nblame a1b2c3d", "composed " .. vim.inspect(text))
  end,

  ["composes nothing from no parts"] = function()
    assert(compose.compose_text({}) == "", "composed " .. vim.inspect(compose.compose_text({})))
  end,

  ["hands the store one flattened line and decorates the id it gave back"] = function()
    -- The sink is the one place that knows what herdr-nvim can render: it joins
    -- with the separator on the way in, anchors the comment to the one line it
    -- was given, and passes the id straight to `ui.decorate`. An annotation
    -- stored and not decorated leaves no mark in the buffer.
    local added, decorated, ok, id = with_fake_store(function()
      return annotate.store(7, 42, {
        mention = "@init.lua:42",
        diagnostic = "ERROR: undefined variable",
        blame = "blame a1b2c3d",
      })
    end)

    assert(ok, id)
    assert(
      added.text == "@init.lua:42 | ERROR: undefined variable | blame a1b2c3d",
      "stored " .. vim.inspect(added.text)
    )
    assert(added.bufnr == 7, "stored in buffer " .. vim.inspect(added.bufnr))
    assert(added.start_line == 42 and added.end_line == 42, "stored over " .. vim.inspect(added))
    assert(decorated == 4242, "decorated " .. vim.inspect(decorated))
    assert(id == 4242, "returned " .. vim.inspect(id))
  end,

  ["walks up to the enclosing function node"] = function()
    local node = chain({ "identifier", "arguments", "function_declaration", "chunk" })
    local found = compose.enclosing_function(node)
    assert(found and found:type() == "function_declaration", "found " .. tostring(found and found:type()))
  end,

  ["reads the cursor node itself as the enclosing function"] = function()
    local found = compose.enclosing_function(chain({ "function_definition", "chunk" }))
    assert(found and found:type() == "function_definition", "found " .. tostring(found and found:type()))
  end,

  ["stops at the innermost function-shaped ancestor"] = function()
    local node = chain({ "identifier", "method_definition", "class_definition", "function_declaration" })
    local found = compose.enclosing_function(node)
    assert(found and found:type() == "method_definition", "found " .. tostring(found and found:type()))
  end,

  ["finds no function outside one"] = function()
    assert(compose.enclosing_function(chain({ "identifier", "table_constructor", "chunk" })) == nil)
    assert(compose.enclosing_function(nil) == nil)
  end,

  ["does not read a merely function-adjacent node as a function"] = function()
    -- The rule is a SUFFIX match, so `function_call` and `parameters` are not
    -- functions; a plain `find` on "function" would take the first of these.
    local node = chain({ "identifier", "function_call", "parameters", "function_definition" })
    local found = compose.enclosing_function(node)
    assert(found and found:type() == "function_definition", "found " .. tostring(found and found:type()))
  end,

  ["covers the function node of every language it handles"] = function()
    -- Measured against the installed grammars, one sample file each: Rust
    -- names its functions `function_item`, Go methods `method_declaration`,
    -- and a named TypeScript function expression `function_expression`. None
    -- of the three ends in a Lua or Python spelling.
    for _, node_type in ipairs({
      "function_definition",
      "function_declaration",
      "method_definition",
      "function_item",
      "method_declaration",
      "function_expression",
    }) do
      local found = compose.enclosing_function(chain({ "identifier", node_type }))
      assert(found and found:type() == node_type, node_type .. " is not read as a function")
    end
  end,

  ["reads a suffix only at the end of the node type"] = function()
    -- `function_definition_call` CONTAINS a listed suffix without ending in
    -- one. A literal substring search would stop here and name the call site
    -- as the enclosing function.
    local node = chain({ "identifier", "function_definition_call", "function_declaration" })
    local found = compose.enclosing_function(node)
    assert(found and found:type() == "function_declaration", "found " .. tostring(found and found:type()))
  end,

  ["annotates a named file buffer"] = function()
    assert(compose.annotatable("lua/herdr-nvim-annotate-extension/init.lua", "") == true)
  end,

  ["annotates a named file that has never been written"] = function()
    -- A new file that has been typed into is a real path with real lines,
    -- and the mention it produces is one an agent can open.
    assert(compose.annotatable("notes.md", "") == true)
  end,

  ["refuses a buffer with no file name"] = function()
    -- The mention would be `@:1`, which names nothing.
    local ok, reason = compose.annotatable("", "")
    assert(ok == false, "annotatable returned " .. tostring(ok))
    assert(type(reason) == "string" and reason ~= "", "reason " .. vim.inspect(reason))
  end,

  ["refuses a buffer that is not a file"] = function()
    -- Every non-empty `buftype` is something other than a file on disk: a
    -- scratch buffer, a terminal, a quickfix list, a help window.
    for _, buftype in ipairs({ "nofile", "nowrite", "acwrite", "terminal", "quickfix", "help", "prompt" }) do
      local ok, reason = compose.annotatable("/tmp/x.lua", buftype)
      assert(ok == false, buftype .. " was accepted")
      assert(type(reason) == "string" and reason ~= "", buftype .. " gave no reason")
    end
  end,

  ["refuses a buffer whose name is a URI rather than a path"] = function()
    -- Measured: an Oil directory buffer and a Fugitive revision buffer both
    -- carry an EMPTY `buftype`, so the buftype rule above does not reach them.
    -- Their names are what gives them away.
    for _, name in ipairs({
      "oil:///Users/stephen/src/",
      "fugitive://./.git//5ef4e631b3f43a2ad5bbbdac634bdfad7a432706/nested.lua",
      "term://~//12345:bash",
      "octo://webdavis/dotfiles/pull/350",
    }) do
      local ok, reason = compose.annotatable(name, "")
      assert(ok == false, name .. " was accepted")
      assert(type(reason) == "string" and reason ~= "", name .. " gave no reason")
    end
  end,

  ["annotates a path that merely contains a colon"] = function()
    -- The scheme is anchored at the start, so a legal filename holding `://`
    -- further along is still a path.
    assert(compose.annotatable("/tmp/a:b/x.lua", "") == true)
    assert(compose.annotatable("notes/http://example.md", "") == true)
  end,

  ["stores no newline, whatever the source spelled across lines"] = function()
    -- Lua lets a declaration wrap, so the `name` field can span lines and the
    -- function part carried the break into the stored text. herdr-nvim builds
    -- one buffer line per comment, so one newline anywhere in the annotation
    -- takes the whole comment list down.
    local text = annotated({
      "local foo = {}",
      "function foo",
      "  .bar()",
      "  return 1",
      "end",
    }, { 4, 2 })
    assert(not text:find("\n", 1, true), "stored a newline: " .. vim.inspect(text))
    assert(text:find("function foo .bar", 1, true), "annotated with " .. vim.inspect(text))
  end,

  ["reads the function at the cursor's column, not at the start of its line"] = function()
    -- Column zero of a nested declaration line sits outside the function being
    -- declared, so this reported the function AROUND it.
    local text = annotated(NESTED, { 2, 18 })
    assert(text:find("function inner", 1, true), "annotated with " .. vim.inspect(text))
  end,

  ["names the severity beside the diagnostic message"] = function()
    local line = compose.diagnostic_line({ severity = vim.diagnostic.severity.WARN, message = "unused local" })
    assert(line == "WARN: unused local", "diagnostic line " .. vim.inspect(line))
  end,

  ["collapses a multi-line diagnostic message onto one line"] = function()
    -- Every part is one line by contract, and a language server is free to
    -- send a message spanning several.
    local line = compose.diagnostic_line({
      severity = vim.diagnostic.severity.ERROR,
      message = "expected type\n  found string",
    })
    assert(line == "ERROR: expected type found string", "diagnostic line " .. vim.inspect(line))
  end,

  ["has no diagnostic part when the message is only whitespace"] = function()
    -- A linter that reports a blank message would otherwise contribute the
    -- bare severity label, `ERROR: `, as a part of its own.
    assert(compose.diagnostic_line({ severity = vim.diagnostic.severity.ERROR, message = "   " }) == nil)
    assert(compose.diagnostic_line({ severity = vim.diagnostic.severity.ERROR, message = "" }) == nil)
  end,

  ["has no diagnostic part without a diagnostic"] = function()
    assert(compose.diagnostic_line(nil) == nil)
  end,

  ["names the blame commit when the line was last touched by HEAD"] = function()
    local line = compose.blame_line("a1b2c3d4e5f6", { hash = "a1b2c3d", summary = "add the annotator" })
    assert(line == "blame a1b2c3d add the annotator", "blame line " .. vim.inspect(line))
  end,

  ["gives the blame sha alone when HEAD is a different commit"] = function()
    -- `git.head_commit` only ever describes HEAD, so attaching its summary to
    -- an older blame sha would caption the line with the wrong commit message.
    local line = compose.blame_line("a1b2c3d4e5f6", { hash = "9999999", summary = "unrelated work" })
    assert(line == "blame a1b2c3d", "blame line " .. vim.inspect(line))
  end,

  ["gives the blame sha alone when HEAD could not be read"] = function()
    assert(compose.blame_line("a1b2c3d4e5f6", nil) == "blame a1b2c3d")
    assert(compose.blame_line("a1b2c3d4e5f6", { hash = "a1b2c3d" }) == "blame a1b2c3d")
  end,

  ["has no blame part without a sha"] = function()
    assert(compose.blame_line(nil, { hash = "a1b2c3d", summary = "add the annotator" }) == nil)
  end,
}
