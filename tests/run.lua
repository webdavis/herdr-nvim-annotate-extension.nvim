local tests_dir = arg[0]:match("(.*)/") or "."
local project_root = tests_dir .. "/.."
local only = arg[1]

package.path = ("%s/lua/?.lua;%s/lua/?/init.lua;%s/?.lua;%s"):format(
  project_root,
  project_root,
  tests_dir,
  package.path
)

local spec_files
if only then
  spec_files = { ("%s/%s.lua"):format(tests_dir, only) }
else
  spec_files = vim.fn.glob(tests_dir .. "/*_spec.lua", false, true)
end

if #spec_files == 0 then
  error("no spec files matched under " .. tests_dir)
end

local failures = 0

local function write_line_to_stdout(line)
  io.write(line, "\n")
end

local function sorted_names(cases)
  local names = vim.tbl_keys(cases)
  table.sort(names)

  return names
end

for _, path in ipairs(spec_files) do
  local spec = path:match("([^/]+)%.lua$")
  local cases = dofile(path)

  if type(cases) ~= "table" or next(cases) == nil then
    error(spec .. " returned no cases")
  end

  for _, name in ipairs(sorted_names(cases)) do
    local ok, err = pcall(cases[name])
    if ok then
      write_line_to_stdout(("ok %s: %s"):format(spec, name))
    else
      failures = failures + 1
      write_line_to_stdout(("FAIL %s: %s: %s"):format(spec, name, err))
    end
  end
end

os.exit(failures == 0 and 0 or 1)
