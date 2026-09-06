# herdr-nvim-annotate-extension.nvim

Annotate the line under the cursor with what an agent would otherwise make you retype: the path and
line number, the diagnostic sitting on it, the function it lives inside, and the commit that last
touched it.

The annotation goes into [herdr-nvim](https://github.com/ChmaraX/herdr-nvim)'s comment store, so
herdr-nvim's own keys list it, paste it and send it. Nothing here types at an agent.

A stored annotation looks like this:

```
@lua/config/lsp.lua:118 | ERROR: undefined global `vim_opt` | function M.setup | blame 4f2a91c wire the language servers
```

A part that does not apply is left out instead of written empty, so a line with no diagnostic and no
commit behind it annotates as `@lua/config/lsp.lua:118` on its own.

## Requirements

- Neovim new enough to have `vim.system`, `vim.uv` and `vim.health`. Developed and tested on 0.12.5.
- [ChmaraX/herdr-nvim](https://github.com/ChmaraX/herdr-nvim), which owns the store the annotation
  goes into.
- `git` on `PATH`, for the blame part. Without it the other three parts still work.
- A treesitter parser attached to the buffer, for the function part.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "webdavis/herdr-nvim-annotate-extension.nvim",
  dependencies = { "ChmaraX/herdr-nvim" },
  keys = {
    { "<leader>Cx", "<cmd>HerdrAnnotateLine<cr>", desc = "Annotate line with diagnostic and blame" },
  },
}
```

There is no `setup()` call. That `keys` row is the whole configuration, and `<leader>Cx` is only an
example: bind whichever key is free in your own layout.

## Usage

`:HerdrAnnotateLine` annotates the cursor's line and decorates it in the buffer. After that the
annotation belongs to herdr-nvim, whose keys list the pending comments, paste them into an agent's
input, or send them.

Three kinds of buffer produce no file reference worth annotating, and the command refuses them with a
message saying which one it hit: a buffer with no name, a buffer with any `buftype` (a terminal, a
quickfix list, a help window), and a buffer whose name is a URI rather than a path, such as an
`oil://` directory listing.

Run `:checkhealth herdr-nvim-annotate-extension` to see whether herdr-nvim is loadable and whether
git is on `PATH`.

## Lua API

```lua
local annotate = require("herdr-nvim-annotate-extension")

annotate.line()                      --> id, or nil plus the reason the buffer was refused
annotate.store(bufnr, line, parts)   --> id, after joining the parts and decorating them
annotate.PART_SEPARATOR              --> " | "
```

`line()` notifies nothing, which is what lets a config route a refusal through its own error
handling. `:HerdrAnnotateLine` is the wrapper that reports one.

The parts land on a single line because herdr-nvim's comment list builds one buffer line per comment,
and `nvim_buf_set_lines` rejects a string holding a newline. Set `PART_SEPARATOR` to `"\n"` once
herdr-nvim can render a multi-line comment, or to anything else you would rather read.

`require("herdr-nvim-annotate-extension.compose")` holds the pure half: `compose_text`,
`enclosing_function`, `blame_line`, `diagnostic_line` and `annotatable`. None of them touch a buffer,
so you can call and test them on their own.

## Tests

```bash
nvim --headless --clean -l tests/run.lua
```

`--clean` matters here. Everything except the sink has to hold with no plugin installed at all, and
the sink runs against a fake herdr-nvim in `package.loaded`.

## License

MIT. See [LICENSE](LICENSE).
