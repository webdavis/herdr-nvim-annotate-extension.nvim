-- `:checkhealth herdr-nvim-annotate-extension`
--
-- Two things have to be true for an annotation to be written and read: the
-- store it goes into has to exist, and git has to be callable. Everything else
-- degrades to a missing part rather than a failure.

local M = {}

function M.check()
  vim.health.start("herdr-nvim-annotate-extension")

  local ok, err = pcall(require, "herdr-nvim.comments")
  if ok then
    vim.health.ok("herdr-nvim is loadable")
  else
    -- The first line only: a `require` failure carries the whole Lua search
    -- path behind it, which buries the one sentence that matters.
    local first_line = tostring(err):match("^[^\n]*")
    vim.health.error("herdr-nvim is not loadable: " .. first_line, {
      "Install ChmaraX/herdr-nvim, or declare it as a dependency of this plugin.",
    })
  end

  if vim.fn.executable("git") == 1 then
    vim.health.ok("git is on PATH")
  else
    vim.health.warn("git is not on PATH", {
      "Annotations still carry the file, the diagnostic and the function.",
      "The blame part is the only one that needs git.",
    })
  end
end

return M
