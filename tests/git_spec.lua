local git = require("herdr-nvim-annotate-extension.git")
local repo = require("repo")

local UNCOMMITTED_PORCELAIN =
  "%s 1 1 1\nauthor Not Committed Yet\nsummary Version of notes.txt from notes.txt\n\tfirst line"

local function blamed(opts)
  local commit = git.blame(opts)
  return commit and commit.summary
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

  ["blames an unchanged crlf file as committed"] = function()
    local file = repo.committed("first line\r\nsecond line\r\n")
    assert(blamed({ file = file, line = 2 }) == "write the notes", vim.inspect(git.blame({ file = file, line = 2 })))
  end,

  ["blames a file with no final newline as committed"] = function()
    local file = repo.committed("first line\nsecond line")
    assert(blamed({ file = file, line = 2 }) == "write the notes", vim.inspect(git.blame({ file = file, line = 2 })))
  end,

  ["reports nothing for a line edited on disk"] = function()
    local file = repo.committed("first line\nsecond line\n")
    repo.write(file, "first line\nchanged\n")
    assert(blamed({ file = file, line = 1 }) == "write the notes", vim.inspect(git.blame({ file = file, line = 1 })))
    assert(blamed({ file = file, line = 2 }) == nil, vim.inspect(git.blame({ file = file, line = 2 })))
  end,

  ["blames a symlinked file as its target"] = function()
    local file = repo.committed("first line\n")
    local link = vim.fs.dirname(file) .. "/link.txt"
    assert(vim.uv.fs_symlink(file, link))
    assert(blamed({ file = link, line = 1 }) == "write the notes", vim.inspect(git.blame({ file = link, line = 1 })))
  end,

  ["blames the unsaved text it is handed instead of the file"] = function()
    local file = repo.committed("first line\nsecond line\n")
    local contents = "first line\nchanged\n"
    local first = git.blame({ file = file, line = 1, contents = contents })
    local second = git.blame({ file = file, line = 2, contents = contents })
    assert(first and first.summary == "write the notes", vim.inspect(first))
    assert(second == nil, vim.inspect(second))
  end,

  ["reports nothing for a line of zero sha digits, whatever their count"] = function()
    for _, zeros in ipairs({ ("0"):rep(40), ("0"):rep(64) }) do
      local commit = git.blame({ file = vim.fn.tempname() .. ".txt", line = 1 }, function()
        return 0, UNCOMMITTED_PORCELAIN:format(zeros)
      end)
      assert(commit == nil, #zeros .. " zeros blamed as " .. vim.inspect(commit))
    end
  end,

  ["reports nothing for output that does not open with a sha and a space"] = function()
    local commit = git.blame({ file = vim.fn.tempname() .. ".txt", line = 1 }, function()
      return 0, "fatal: no such path"
    end)
    assert(commit == nil, "blamed as " .. vim.inspect(commit))
  end,
}
