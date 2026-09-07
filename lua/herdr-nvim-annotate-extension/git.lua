-- The git edge, narrowed to the two questions an annotation asks: which commit
-- last touched this line, and what is HEAD called.
--
-- No `vim.fn.system`, no shell text, and no dependency on a git plugin being
-- installed: every call is argv words through `vim.system`, behind one
-- replaceable `M.runner` field.

local M = {}

local compose = require("herdr-nvim-annotate-extension.compose")

-- ╭────────────────╮
-- │  The shell seam │
-- ╰────────────────╯

---Run `opts.cmd` and return its exit code and trimmed output.
---
---`cmd` is argv WORDS, never shell text: nothing here is quoted and every one
---of these commands carries an interpolated path. `stdin` is the text to feed
---the command, which is what lets a caller blame a buffer it has not saved.
---`cwd` is the directory to run in.
---
---Every git call in this module goes through this one field, so a test replaces
---it rather than shelling out.
---@param opts { cmd: string[], stdin: string?, cwd: string? }
---@return integer code
---@return string output
function M.runner(opts)
  local ok, process = pcall(vim.system, opts.cmd, { text = true, stdin = opts.stdin, cwd = opts.cwd })
  if not ok then
    return 127, tostring(process)
  end
  local result = process:wait()

  -- stderr joins the value only on failure, so a tool that warns on stderr
  -- cannot glue its notice onto output the caller is about to read.
  local output = result.stdout or ""
  if result.code ~= 0 then
    output = output .. (result.stderr or "")
  end

  return result.code, compose.trim(output)
end

-- ╭──────────╮
-- │  Helpers │
-- ╰──────────╯

---The directory holding `path`, for a command's `cwd`.
---
---Git answers for the repository of the directory it runs in, not for the
---repository of the path it is handed, so a command about a file has to run
---beside that file. With Neovim's own working directory outside the repository,
---`git blame` on an absolute path inside it reports
---`fatal: not a git repository`.
---
---Symlinks are resolved first, because git answers for the real file: a link
---and its target can sit in two different checkouts. Answers nil for a path
---with no directory of its own, which leaves nvim's cwd in place.
---@param path string?
---@return string?
local function file_dir(path)
  if not path or path == "" then
    return nil
  end

  local dir = vim.fn.fnamemodify(vim.uv.fs_realpath(path) or path, ":p:h")

  return vim.fn.isdirectory(dir) == 1 and dir or nil
end

-- The first porcelain line is `<sha> <orig-line> <final-line> <count>`. Only the
-- SHA is read; `%s` after the token is what keeps a `fatal:` from matching as
-- hex on its leading letters.
local function parse_blame_porcelain(text)
  local sha = (text or ""):match("^(%x+)%s")

  if not sha then
    return nil, "no blame line to read"
  end

  -- What git blame prints as the SHA of a line that is not committed yet is a
  -- SHA of zeros: forty of them in a SHA-1 repository and sixty-four in a
  -- SHA-256 one, so the digits are what identify it and never their count.
  if sha:match("^0+$") then
    return nil, "not committed yet"
  end

  return sha
end

-- What each `fileformat` puts between lines when the buffer is written out.
local LINE_SEPARATOR = { unix = "\n", dos = "\r\n", mac = "\r" }

-- The text the editor is showing for `file`. Blaming the saved copy answers for
-- a line you may have already replaced, so what the buffer holds is
-- what goes to git; git reports a line that is only in the buffer as
-- uncommitted, which is the true answer. `line()` blames the current buffer, so
-- a name that does not match it means there is nothing unsaved.
--
-- These have to be the bytes the file itself would hold, not the lines glued
-- with LF and a newline stapled on: a `fileformat=dos` buffer rejoined with LF,
-- or a file with no trailing newline given one, differs from its own committed
-- blob, so every line of an UNCHANGED file blamed as uncommitted.
local function buffer_contents(file)
  if vim.api.nvim_buf_get_name(0) ~= file then
    return nil
  end

  -- `binary` writes the buffer out with LF between the lines whatever
  -- `fileformat` says, so it settles the separator before the format is read.
  local separator = vim.bo.binary and "\n" or (LINE_SEPARATOR[vim.bo.fileformat] or "\n")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- A `fileformat=mac` buffer is split on carriage returns, and nvim shows an LF
  -- byte sitting INSIDE one of those lines as a carriage return as well. Joining
  -- with a carriage return would write the file's own LF back out as a line
  -- break, so the two are told apart here: a carriage return still inside a line
  -- is the LF it was read from.
  if separator == "\r" then
    lines = vim.tbl_map(function(line)
      return (line:gsub("\r", "\n"))
    end, lines)
  end

  local text = table.concat(lines, separator)

  return vim.bo.endofline and text .. separator or text
end

-- ╭──────╮
-- │  API │
-- ╰──────╯

---The SHA of the commit that last touched `line` of `file`.
---@param opts { file: string, line: integer }
---@return string? sha
---@return string? err
function M.blame_sha(opts)
  local file = opts.file
  local line = opts.line

  local range = ("%d,%d"):format(line, line)
  local contents = buffer_contents(file)

  -- A symlink gives nvim the TARGET's text under the LINK's name, and the link's
  -- own blob holds a path rather than that text, so blaming the link compared
  -- the two and called every line uncommitted. The link's name is what the
  -- buffer is called and stays the key for matching it; git gets the real file.
  local blamed = vim.uv.fs_realpath(file) or file

  local cmd = { "git", "blame", "-L", range, "--porcelain" }
  if contents then
    vim.list_extend(cmd, { "--contents", "-" })
  end
  vim.list_extend(cmd, { "--", blamed })

  local code, output = M.runner({ cmd = cmd, stdin = contents, cwd = file_dir(blamed) })

  if code ~= 0 then
    return nil, output
  end

  return parse_blame_porcelain(output)
end

---HEAD's short hash and subject in the repository holding `file`.
---
---One `git log` rather than a `rev-parse` and a `log`: the hash and the subject
---are two fields of one commit, and asking twice forks twice on every
---annotation. A commit with no subject line yields a hash and no summary, which
---is what `compose.blame_line` renders as a bare SHA.
---@param file string the file whose repository to read HEAD from
---@return { hash: string, summary: string? }?
---@return string? err
function M.head_commit(file)
  local code, output = M.runner({ cmd = { "git", "log", "-1", "--pretty=%h%n%s" }, cwd = file_dir(file) })

  if code ~= 0 then
    return nil, output
  end

  local hash, summary = output:match("^(%S+)\n?(.*)$")
  if not hash then
    return nil, "HEAD has no commit to read"
  end

  summary = compose.one_line(summary)

  return { hash = hash, summary = summary ~= "" and summary or nil }
end

return M
