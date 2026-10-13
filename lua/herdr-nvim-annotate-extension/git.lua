-- No `vim.fn.system`, no shell text, and no dependency on a git plugin being
-- installed: every call is argv words through `vim.system`, behind one
-- replaceable `M.runner` field.

local M = {}

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

  return result.code, vim.trim(result.stdout or "")
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
---Answers nil for a path with no directory of its own, which leaves nvim's cwd
---in place.
---@param path string?
---@return string?
local function file_dir(path)
  if not path or path == "" then
    return nil
  end

  local dir = vim.fn.fnamemodify(path, ":p:h")

  return vim.fn.isdirectory(dir) == 1 and dir or nil
end

-- The first porcelain line is `<sha> <orig-line> <final-line> <count>`. `%s`
-- after the token is what keeps a `fatal:` from matching as hex on its leading
-- letters.
local function parse_blame_porcelain(text)
  local sha = text:match("^(%x+)%s")

  if not sha or sha:match("^0+$") then
    return nil
  end

  local summary = text:match("\nsummary ([^\n]*)")

  return { sha = sha, summary = summary ~= "" and summary or nil }
end

-- ╭──────╮
-- │  API │
-- ╰──────╯

---@param opts { file: string, line: integer, contents: string? }
---@param run? fun(opts: { cmd: string[], stdin: string?, cwd: string? }): integer, string
---@return { sha: string, summary: string? }? commit
function M.blame(opts, run)
  local file = opts.file
  local line = opts.line

  local range = ("%d,%d"):format(line, line)
  local contents = opts.contents

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

  local code, output = (run or M.runner)({ cmd = cmd, stdin = contents, cwd = file_dir(blamed) })

  if code ~= 0 then
    return nil
  end

  return parse_blame_porcelain(output)
end

return M
