local target = require("herdr-nvim-annotate-extension.target")

return {
  ["annotates a named file buffer"] = function()
    assert(target.annotatable("lua/herdr-nvim-annotate-extension/init.lua", "") == true)
  end,

  ["annotates a named file that has never been written"] = function()
    assert(target.annotatable("notes.md", "") == true)
  end,

  ["refuses a buffer with no file name"] = function()
    local ok, reason = target.annotatable("", "")
    assert(ok == false, "annotatable returned " .. tostring(ok))
    assert(type(reason) == "string" and reason ~= "", "reason " .. vim.inspect(reason))
  end,

  ["refuses a buffer that is not a file"] = function()
    for _, buftype in ipairs({ "nofile", "nowrite", "acwrite", "terminal", "quickfix", "help", "prompt" }) do
      local ok, reason = target.annotatable("/tmp/x.lua", buftype)
      assert(ok == false, buftype .. " was accepted")
      assert(type(reason) == "string" and reason ~= "", buftype .. " gave no reason")
    end
  end,

  ["says in a sentence that a buffer with a buftype is not a file on disk"] = function()
    local _, reason = target.annotatable("/tmp/x.lua", "nofile")
    assert(reason == "this buffer is not a file on disk (buftype=nofile)", "reason " .. vim.inspect(reason))
  end,

  ["refuses a buffer whose name is a URI rather than a path"] = function()
    for _, name in ipairs({
      "oil:///Users/stephen/src/",
      "fugitive://./.git//5ef4e631b3f43a2ad5bbbdac634bdfad7a432706/nested.lua",
      "term://~//12345:bash",
      "octo://webdavis/dotfiles/pull/350",
    }) do
      local ok, reason = target.annotatable(name, "")
      assert(ok == false, name .. " was accepted")
      assert(type(reason) == "string" and reason ~= "", name .. " gave no reason")
    end
  end,

  ["annotates a path that merely contains a colon"] = function()
    assert(target.annotatable("/tmp/a:b/x.lua", "") == true)
    assert(target.annotatable("notes/http://example.md", "") == true)
  end,
}
