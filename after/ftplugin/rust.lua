local keymap = vim.keymap
local bufnr = vim.api.nvim_get_current_buf()
local map = function(mode, l, r, opts)
  opts = opts or {}
  opts.silent = true
  opts.buffer = bufnr
  keymap.set(mode, l, r, opts)
end

map("n", "<space>cs", function() vim.cmd.RustLsp('codeAction') end, { desc = "rustaceanvim rust-analyzer's grouping" })
