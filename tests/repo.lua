local GIT_ENV = {
  GIT_CONFIG_GLOBAL = "/dev/null",
  GIT_CONFIG_SYSTEM = "/dev/null",
  GIT_AUTHOR_NAME = "t",
  GIT_AUTHOR_EMAIL = "t@t",
  GIT_COMMITTER_NAME = "t",
  GIT_COMMITTER_EMAIL = "t@t",
}

local M = {}

function M.run(dir, ...)
  local result = vim.system({ ... }, { cwd = dir, env = GIT_ENV, text = true }):wait()
  assert(result.code == 0, result.stderr)

  return vim.trim(result.stdout)
end

function M.write(file, bytes)
  local handle = assert(io.open(file, "wb"))
  handle:write(bytes)
  handle:close()
end

function M.new()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  M.run(dir, "git", "init", "-q")
  M.run(dir, "git", "config", "core.autocrlf", "false")

  return dir
end

function M.commit(dir, name, bytes, message)
  local file = dir .. "/" .. name
  M.write(file, bytes)
  M.run(dir, "git", "add", name)
  M.run(dir, "git", "commit", "-q", "-m", message)

  return file, M.run(dir, "git", "rev-parse", "HEAD")
end

function M.committed(bytes)
  return M.commit(M.new(), "notes.txt", bytes, "write the notes")
end

return M
