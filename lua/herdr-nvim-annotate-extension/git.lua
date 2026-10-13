local M = {}

local SHA_THEN_SPACE = "^(%x+)%s"

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

---@param path string?
---@return string?
local function file_dir(path)
  if not path or path == "" then
    return nil
  end

  local dir = vim.fn.fnamemodify(path, ":p:h")

  return vim.fn.isdirectory(dir) == 1 and dir or nil
end

local function parse_blame_porcelain(text)
  local sha = text:match(SHA_THEN_SPACE)

  if not sha or sha:match("^0+$") then
    return nil
  end

  local summary = text:match("\nsummary ([^\n]*)")

  return { sha = sha, summary = summary ~= "" and summary or nil }
end

---@param opts { file: string, line: integer, contents: string? }
---@param run? fun(opts: { cmd: string[], stdin: string?, cwd: string? }): integer, string
---@return { sha: string, summary: string? }? commit
function M.blame(opts, run)
  local file = opts.file
  local line = opts.line

  local range = ("%d,%d"):format(line, line)
  local contents = opts.contents

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
