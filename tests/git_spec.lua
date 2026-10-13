local git = require("herdr-nvim-annotate-extension.git")

local GIT_ENV = {
  GIT_CONFIG_GLOBAL = "/dev/null",
  GIT_CONFIG_SYSTEM = "/dev/null",
  GIT_AUTHOR_NAME = "t",
  GIT_AUTHOR_EMAIL = "t@t",
  GIT_COMMITTER_NAME = "t",
  GIT_COMMITTER_EMAIL = "t@t",
}

local UNCOMMITTED_PORCELAIN =
  "%s 1 1 1\nauthor Not Committed Yet\nsummary Version of notes.txt from notes.txt\n\tfirst line"

local function run(dir, ...)
  local result = vim.system({ ... }, { cwd = dir, env = GIT_ENV, text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end

local function write(file, bytes)
  local handle = assert(io.open(file, "wb"))
  handle:write(bytes)
  handle:close()
end

local function committed(bytes)
  local dir = vim.fn.tempname()
  local file = dir .. "/notes.txt"
  vim.fn.mkdir(dir, "p")
  write(file, bytes)
  run(dir, "git", "init", "-q")
  run(dir, "git", "config", "core.autocrlf", "false")
  run(dir, "git", "add", "notes.txt")
  run(dir, "git", "commit", "-q", "-m", "write the notes")
  return file, run(dir, "git", "rev-parse", "HEAD")
end

local function blamed(opts)
  local commit = git.blame(opts)
  return commit and commit.summary
end

local function with_runner(runner, body)
  local previous = git.runner
  git.runner = runner
  local ok, result = pcall(body)
  git.runner = previous
  assert(ok, result)
  return result
end

return {
  ["returns a spawn failure through the normal command error result"] = function()
    local previous = vim.system
    vim.system = function()
      error("spawn failed: ENOENT")
    end
    local ok, code, output = pcall(git.runner, { cmd = { "git", "status" } })
    vim.system = previous
    assert(ok, code)
    assert(type(code) == "number" and code ~= 0, "spawn failure returned " .. tostring(code))
    assert(output:find("spawn failed: ENOENT", 1, true), "lost spawn failure: " .. tostring(output))
  end,

  ["keeps successful output separate from stderr after spawning"] = function()
    local previous = vim.system
    vim.system = function()
      return {
        wait = function()
          return { code = 0, stdout = "  answer\n", stderr = "warning" }
        end,
      }
    end
    local ok, code, output = pcall(git.runner, { cmd = { "git", "status" } })
    vim.system = previous
    assert(ok, code)
    assert(code == 0 and output == "answer", vim.inspect({ code, output }))
  end,

  ["retains command stderr when the spawned command fails"] = function()
    local previous = vim.system
    vim.system = function()
      return {
        wait = function()
          return { code = 128, stdout = "out\n", stderr = "fatal: no repository\n" }
        end,
      }
    end
    local ok, code, output = pcall(git.runner, { cmd = { "git", "status" } })
    vim.system = previous
    assert(ok, code)
    assert(code == 128 and output == "out\nfatal: no repository", vim.inspect({ code, output }))
  end,

  ["blames an unchanged crlf file as committed"] = function()
    local file = committed("first line\r\nsecond line\r\n")
    assert(blamed({ file = file, line = 2 }) == "write the notes", vim.inspect(git.blame({ file = file, line = 2 })))
  end,

  ["blames a file with no final newline as committed"] = function()
    local file = committed("first line\nsecond line")
    assert(blamed({ file = file, line = 2 }) == "write the notes", vim.inspect(git.blame({ file = file, line = 2 })))
  end,

  ["reports nothing for a line edited on disk"] = function()
    local file = committed("first line\nsecond line\n")
    write(file, "first line\nchanged\n")
    assert(blamed({ file = file, line = 1 }) == "write the notes", vim.inspect(git.blame({ file = file, line = 1 })))
    assert(blamed({ file = file, line = 2 }) == nil, vim.inspect(git.blame({ file = file, line = 2 })))
  end,

  ["blames a symlinked file as its target"] = function()
    local file = committed("first line\n")
    local link = vim.fs.dirname(file) .. "/link.txt"
    assert(vim.uv.fs_symlink(file, link))
    assert(blamed({ file = link, line = 1 }) == "write the notes", vim.inspect(git.blame({ file = link, line = 1 })))
  end,

  ["reports nothing for a line of zero sha digits, whatever their count"] = function()
    for _, zeros in ipairs({ ("0"):rep(40), ("0"):rep(64) }) do
      local commit = with_runner(function()
        return 0, UNCOMMITTED_PORCELAIN:format(zeros)
      end, function()
        return git.blame({ file = vim.fn.tempname() .. ".txt", line = 1 })
      end)
      assert(commit == nil, #zeros .. " zeros blamed as " .. vim.inspect(commit))
    end
  end,
}
