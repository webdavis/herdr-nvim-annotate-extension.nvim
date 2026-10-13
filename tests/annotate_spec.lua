local annotate = require("herdr-nvim-annotate-extension")
local comments = require("herdr-nvim.comments")
local repo = require("repo")
local ui = require("herdr-nvim.ui")

local TARGET = { bufnr = 3, name = "/tmp/init.lua", line = 42, column = 0 }

local function sink()
  local fake = {}
  function fake.store(target, text)
    fake.target, fake.text = target, text
    return 4242
  end
  return fake
end

local function parts(...)
  return vim.tbl_map(function(value)
    return function()
      return value
    end
  end, { ... })
end

local function annotated(given)
  local fake = sink()
  annotate.annotate(TARGET, given, fake)
  return fake.text
end

local function line_of(file, cursor)
  vim.cmd({ cmd = "edit", args = { file }, bang = true, mods = { silent = true } })
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].filetype = "lua"
  vim.treesitter.get_parser(bufnr, "lua"):parse()
  vim.api.nvim_win_set_cursor(0, cursor)
  vim.diagnostic.set(vim.api.nvim_create_namespace("annotate-spec"), bufnr, {
    { lnum = cursor[1] - 1, col = 0, severity = vim.diagnostic.severity.WARN, message = "first\nsecond" },
  })
  local mention = "@" .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
  local ok, id, reason = pcall(annotate.line)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  assert(ok, id)
  assert(id, "the annotator refused the buffer: " .. tostring(reason))
  assert(ui.decorated[#ui.decorated] == id, "decorated " .. vim.inspect(ui.decorated))
  return comments.added[id].text, mention
end

local ANSWER = "local function answer()\n  return 1\nend\n"

return {
  ["joins every part, in the order given, with a pipe"] = function()
    local text = annotated(parts("first", "second", "third", "fourth"))
    assert(text == "first | second | third | fourth", "composed " .. vim.inspect(text))
  end,

  ["returns just the mention when it is the only part"] = function()
    local text = annotated(parts("@init.lua:1"))
    assert(text == "@init.lua:1", "composed " .. vim.inspect(text))
  end,

  ["leaves no gap where a part has nothing"] = function()
    local text = annotated(parts("@init.lua:1", nil, "function setup", "blame a1b2c3d"))
    assert(text == "@init.lua:1 | function setup | blame a1b2c3d", "composed " .. vim.inspect(text))
  end,

  ["treats an empty part as no part"] = function()
    local text = annotated(parts("@init.lua:1", "", "blame a1b2c3d"))
    assert(text == "@init.lua:1 | blame a1b2c3d", "composed " .. vim.inspect(text))
  end,

  ["composes nothing from no parts"] = function()
    local text = annotated({})
    assert(text == "", "composed " .. vim.inspect(text))
  end,

  ["flattens embedded line breaks in every part"] = function()
    local text = annotated(parts("@first\nsecond:42", "ERROR: first\r\nsecond", "function first\rsecond"))
    assert(text == "@first second:42 | ERROR: first second | function first second", "composed " .. vim.inspect(text))
  end,

  ["omits a part that becomes empty when flattened"] = function()
    local text = annotated(parts("@init.lua:42", " \r\n\t ", "blame a1b2c3d"))
    assert(text == "@init.lua:42 | blame a1b2c3d", "composed " .. vim.inspect(text))
  end,

  ["hands the sink the target and returns the id it gave back"] = function()
    local fake = sink()
    local id = annotate.annotate(TARGET, {
      function(target)
        return "@init.lua:" .. target.line
      end,
    }, fake)
    assert(id == 4242, "returned " .. vim.inspect(id))
    assert(fake.target == TARGET, "stored against " .. vim.inspect(fake.target))
    assert(fake.text == "@init.lua:42", "stored " .. vim.inspect(fake.text))
  end,

  ["orders the parts mention, diagnostic, function, blame"] = function()
    local file, sha = repo.commit(repo.new(), "answer.lua", ANSWER, "write the answer")
    local text, mention = line_of(file, { 2, 2 })
    local expected = ("%s:2 | WARN: first second | function answer | blame %s write the answer"):format(
      mention,
      sha:sub(1, 7)
    )
    assert(text == expected, "stored " .. vim.inspect(text))
  end,

  ["missing git preserves the editor parts and stores without notifying"] = function()
    local file = vim.fn.tempname() .. ".lua"
    repo.write(file, ANSWER)
    local previous_path, previous_notify = vim.env.PATH, vim.notify
    local notices = {}
    vim.notify = function(message)
      notices[#notices + 1] = message
    end
    vim.env.PATH = vim.fn.tempname()
    local ok, text, mention = pcall(line_of, file, { 2, 2 })
    vim.env.PATH, vim.notify = previous_path, previous_notify
    assert(ok, text)
    local expected = mention .. ":2 | WARN: first second | function answer"
    assert(text == expected, "stored " .. vim.inspect(text))
    assert(#notices == 0, "line() notified: " .. vim.inspect(notices))
  end,
}
