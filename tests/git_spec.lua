local git = require("herdr-nvim-annotate-extension.git")

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
}
