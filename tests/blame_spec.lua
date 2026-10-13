local annotate = require("herdr-nvim-annotate-extension")
local compose = require("herdr-nvim-annotate-extension.compose")
local git = require("herdr-nvim-annotate-extension.git")

local PORCELAIN = table.concat({
  "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0 1 1 1",
  "author t",
  "author-mail <t@t>",
  "author-time 1700000000",
  "author-tz +0000",
  "committer t",
  "committer-mail <t@t>",
  "committer-time 1700000000",
  "committer-tz +0000",
  "summary add the annotator",
  "filename notes.txt",
  "\tfirst line",
}, "\n")

local GIT_ENV = {
  GIT_CONFIG_GLOBAL = "/dev/null",
  GIT_CONFIG_SYSTEM = "/dev/null",
  GIT_AUTHOR_NAME = "t",
  GIT_AUTHOR_EMAIL = "t@t",
  GIT_COMMITTER_NAME = "t",
  GIT_COMMITTER_EMAIL = "t@t",
}

local function run(dir, ...)
  local result = vim.system({ ... }, { cwd = dir, env = GIT_ENV, text = true }):wait()
  assert(result.code == 0, result.stderr)
end

local function repo_with_two_commits()
  local dir = vim.fn.tempname()
  local file = dir .. "/notes.txt"
  vim.fn.mkdir(dir, "p")
  run(dir, "git", "init", "-q")
  vim.fn.writefile({ "first line", "second line" }, file)
  run(dir, "git", "add", "notes.txt")
  run(dir, "git", "commit", "-q", "-m", "write the first two lines")
  vim.fn.writefile({ "first line", "second line", "third line" }, file)
  run(dir, "git", "commit", "-q", "-am", "append a third line")
  return file
end

local function stored_text(body)
  local real_comments = package.loaded["herdr-nvim.comments"]
  local real_ui = package.loaded["herdr-nvim.ui"]
  local text
  package.loaded["herdr-nvim.comments"] = {
    add = function(_, _, _, stored)
      text = stored
      return 1
    end,
  }
  package.loaded["herdr-nvim.ui"] = {
    decorate = function() end,
  }
  local ok, id, reason = pcall(body)
  package.loaded["herdr-nvim.comments"] = real_comments
  package.loaded["herdr-nvim.ui"] = real_ui
  assert(ok, id)
  assert(id, "the annotator refused the buffer: " .. tostring(reason))
  return text
end

local function annotated(file, lines, cursor, runner)
  local real_runner = git.runner
  local previous = vim.api.nvim_get_current_buf()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(bufnr, file)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, cursor)
  git.runner = runner or real_runner
  local ok, text = pcall(stored_text, annotate.line)
  git.runner = real_runner
  vim.api.nvim_set_current_buf(previous)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  assert(ok, text)
  return text
end

return {
  ["names the commit that last touched the line, whatever HEAD is"] = function()
    local file = repo_with_two_commits()
    local text = annotated(file, vim.fn.readfile(file), { 1, 0 })
    assert(text:find("write the first two lines", 1, true), "annotated with " .. vim.inspect(text))
    assert(not text:find("append a third line", 1, true), "annotated with HEAD's subject: " .. vim.inspect(text))
  end,

  ["asks git once per annotation"] = function()
    local spawns = 0
    annotated(vim.fn.tempname() .. ".txt", { "first line" }, { 1, 0 }, function()
      spawns = spawns + 1
      return 0, PORCELAIN
    end)
    assert(spawns == 1, "git ran " .. spawns .. " times")
  end,

  ["reads the subject from the blame output"] = function()
    local text = annotated(vim.fn.tempname() .. ".txt", { "first line" }, { 1, 0 }, function()
      return 0, PORCELAIN
    end)
    assert(text:find("blame a1b2c3d add the annotator", 1, true), "annotated with " .. vim.inspect(text))
  end,

  ["names the commit beside its short sha"] = function()
    local line = compose.blame_line({ sha = "a1b2c3d4e5f6", summary = "add the annotator" })
    assert(line == "blame a1b2c3d add the annotator", "blame line " .. vim.inspect(line))
  end,

  ["gives the sha alone when the commit has no subject"] = function()
    assert(compose.blame_line({ sha = "a1b2c3d4e5f6" }) == "blame a1b2c3d")
  end,

  ["has no blame part without a commit"] = function()
    assert(compose.blame_line(nil) == nil)
  end,
}
