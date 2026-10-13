local blame = require("herdr-nvim-annotate-extension.part.blame")
local repo = require("repo")

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

local function part_of(bufnr, run)
  local ok, part = pcall(blame, { bufnr = bufnr, name = vim.api.nvim_buf_get_name(bufnr), line = 1, column = 0 }, run)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  assert(ok, part)
  return part
end

local function unsaved(file, lines)
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(bufnr, file)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local function edited(file)
  vim.cmd({ cmd = "edit", args = { file }, bang = true, mods = { silent = true } })
  return vim.api.nvim_get_current_buf()
end

local function answering(output)
  return function()
    return 0, output
  end
end

return {
  ["names the commit that last touched the line, whatever HEAD is"] = function()
    local dir = repo.new()
    local file, first = repo.commit(dir, "notes.txt", "first line\nsecond line\n", "write the first two lines")
    repo.commit(dir, "notes.txt", "first line\nsecond line\nthird line\n", "append a third line")
    local part = part_of(unsaved(file, vim.fn.readfile(file)))
    assert(part == "blame " .. first:sub(1, 7) .. " write the first two lines", "blame part " .. vim.inspect(part))
  end,

  ["asks git once per annotation"] = function()
    local spawns = 0
    part_of(unsaved(vim.fn.tempname() .. ".txt", { "first line" }), function()
      spawns = spawns + 1
      return 0, PORCELAIN
    end)
    assert(spawns == 1, "git ran " .. spawns .. " times")
  end,

  ["reads the subject from the blame output beside the short sha"] = function()
    local part = part_of(unsaved(vim.fn.tempname() .. ".txt", { "first line" }), answering(PORCELAIN))
    assert(part == "blame a1b2c3d add the annotator", "blame part " .. vim.inspect(part))
  end,

  ["gives the sha alone when the commit has no subject"] = function()
    local without_summary = PORCELAIN:gsub("\nsummary [^\n]*", "")
    local part = part_of(unsaved(vim.fn.tempname() .. ".txt", { "first line" }), answering(without_summary))
    assert(part == "blame a1b2c3d", "blame part " .. vim.inspect(part))
  end,

  ["has no blame part without a commit"] = function()
    local part = part_of(unsaved(vim.fn.tempname() .. ".txt", { "first line" }), function()
      return 128, "fatal: not a git repository"
    end)
    assert(part == nil, "blame part " .. vim.inspect(part))
  end,

  ["blames an unmodified latin-1 file as committed"] = function()
    local file, sha = repo.committed("caf\233\n")
    local part = part_of(edited(file))
    assert(part == "blame " .. sha:sub(1, 7) .. " write the notes", "blame part " .. vim.inspect(part))
  end,
}
