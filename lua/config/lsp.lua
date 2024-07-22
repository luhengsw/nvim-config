local fn = vim.fn
local api = vim.api
local keymap = vim.keymap
local lsp = vim.lsp
local diagnostic = vim.diagnostic

local utils = require("utils")

-- set quickfix list from diagnostics in a certain buffer, not the whole workspace
local set_qflist = function(buf_num, severity)
  local diagnostics = nil
  diagnostics = diagnostic.get(buf_num, { severity = severity })

  local qf_items = diagnostic.toqflist(diagnostics)
  vim.fn.setqflist({}, ' ', { title = 'Diagnostics', items = qf_items })

  -- open quickfix by default
  vim.cmd[[copen]]
end

local custom_attach = function(client, bufnr)
  -- Mappings.
  local map = function(mode, l, r, opts)
    opts = opts or {}
    opts.silent = true
    opts.buffer = bufnr
    keymap.set(mode, l, r, opts)
  end

  map("n", "gd", vim.lsp.buf.definition, { desc = "go to definition" })
  map("n", "<C-]>", vim.lsp.buf.definition)
  map("n", "K", vim.lsp.buf.hover)
  map("n", "<C-k>", vim.lsp.buf.signature_help)
  map("n", "<space>rn", vim.lsp.buf.rename, { desc = "varialbe rename" })
  map("n", "gr", vim.lsp.buf.references, { desc = "show references" })
  map("n", "[d", diagnostic.goto_prev, { desc = "previous diagnostic" })
  map("n", "]d", diagnostic.goto_next, { desc = "next diagnostic" })
  -- this puts diagnostics from opened files to quickfix
  map("n", "<space>qw", diagnostic.setqflist, { desc = "put window diagnostics to qf" })
  -- this puts diagnostics from current buffer to quickfix
  map("n", "<space>qb", function() set_qflist(bufnr) end, { desc = "put buffer diagnostics to qf" })
  map("n", "<space>ca", vim.lsp.buf.code_action, { desc = "LSP code action" })
  map("n", "<space>wa", vim.lsp.buf.add_workspace_folder, { desc = "add workspace folder" })
  map("n", "<space>wr", vim.lsp.buf.remove_workspace_folder, { desc = "remove workspace folder" })
  map("n", "<space>wl", function()
    vim.print(vim.lsp.buf.list_workspace_folders())
  end, { desc = "list workspace folder" })

  -- Set some key bindings conditional on server capabilities
  if client.server_capabilities.documentFormattingProvider then
    map("n", "<space>f", vim.lsp.buf.format, { desc = "format code" })
  end

  api.nvim_create_autocmd("CursorHold", {
    buffer = bufnr,
    callback = function()
      local float_opts = {
        focusable = false,
        close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
        border = "rounded",
        source = "always", -- show source in diagnostic popup window
        prefix = " ",
      }

      if not vim.b.diagnostics_pos then
        vim.b.diagnostics_pos = { nil, nil }
      end

      local cursor_pos = api.nvim_win_get_cursor(0)
      if (cursor_pos[1] ~= vim.b.diagnostics_pos[1] or cursor_pos[2] ~= vim.b.diagnostics_pos[2])
          and #diagnostic.get() > 0
      then
        diagnostic.open_float(nil, float_opts)
      end

      vim.b.diagnostics_pos = cursor_pos
    end,
  })

  -- The blow command will highlight the current variable and its usages in the buffer.
  if client.server_capabilities.documentHighlightProvider then
    vim.cmd([[
      hi! link LspReferenceRead Visual
      hi! link LspReferenceText Visual
      hi! link LspReferenceWrite Visual
    ]])

    local gid = api.nvim_create_augroup("lsp_document_highlight", { clear = true })
    api.nvim_create_autocmd("CursorHold" , {
      group = gid,
      buffer = bufnr,
      callback = function ()
        lsp.buf.document_highlight()
      end
    })

    api.nvim_create_autocmd("CursorMoved" , {
      group = gid,
      buffer = bufnr,
      callback = function ()
        lsp.buf.clear_references()
      end
    })
  end

  if vim.g.logging_level == "debug" then
    local msg = string.format("Language server %s started!", client.name)
    vim.notify(msg, vim.log.levels.DEBUG, { title = "Nvim-config" })
  end
end

local capabilities = require('cmp_nvim_lsp').default_capabilities()
-- required by nvim-ufo
capabilities.textDocument.foldingRange = {
    dynamicRegistration = false,
    lineFoldingOnly = true
}

local lspconfig = require("lspconfig")

if utils.executable("pylsp") then
  local venv_path = os.getenv('VIRTUAL_ENV')
  local py_path = nil
  -- decide which python executable to use for mypy
  if venv_path ~= nil then
    py_path = venv_path .. "/bin/python3"
  else
    py_path = vim.g.python3_host_prog
  end

  lspconfig.pylsp.setup {
    on_attach = custom_attach,
    settings = {
      pylsp = {
        plugins = {
          -- formatter options
          black = { enabled = true },
          autopep8 = { enabled = false },
          yapf = { enabled = false },
          -- linter options
          pylint = { enabled = true, executable = "pylint" },
          ruff = { enabled = false },
          pyflakes = { enabled = false },
          pycodestyle = { enabled = false },
          -- type checker
          pylsp_mypy = {
            enabled = true,
            overrides = { "--python-executable", py_path, true },
            report_progress = true,
            live_mode = false
          },
          -- auto-completion options
          jedi_completion = { fuzzy = true },
          -- import sorting
          isort = { enabled = true },
        },
      },
    },
    flags = {
      debounce_text_changes = 200,
    },
    capabilities = capabilities,
  }
else
  vim.notify("pylsp not found!", vim.log.levels.WARN, { title = "Nvim-config" })
end

-- Golang support
if utils.executable('gopls') then
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  capabilities.textDocument.completion.completionItem.snippetSupport = true

  lspconfig.gopls.setup {
    cmd = { 'gopls' },
    -- for postfix snippets and analyzers
    capabilities = capabilities,
    settings = {
      gopls = {
        experimentalPostfixCompletions = true,
        analyses = {
          unusedparams = true,
          shadow = true,
        },
        staticcheck = true,
      },
    },
    on_attach = custom_attach,
  }

  -- use go-vim instead
  ---- go autocmd support for gopls
  --local augroup = vim.api.nvim_create_augroup   -- Create/get autocommand group
  --local autocmd = vim.api.nvim_create_autocmd   -- Create autocommand
  --augroup('golang_support', { clear = true })
  --autocmd("BufWritePre", {
  --  pattern = "*.go",
  --  group = "golang_support",
  --  callback = function()
  --    local params = vim.lsp.util.make_range_params()
  --    params.context = {only = {"source.organizeImports"}}
  --    -- buf_request_sync defaults to a 1000ms timeout. Depending on your
  --    -- machine and codebase, you may want longer. Add an additional
  --    -- argument after params if you find that you have to write the file
  --    -- twice for changes to be saved.
  --    -- E.g., vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 3000)
  --    local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params)
  --    for cid, res in pairs(result or {}) do
  --      for _, r in pairs(res.result or {}) do
  --        if r.edit then
  --          local enc = (vim.lsp.get_client_by_id(cid) or {}).offset_encoding or "utf-16"
  --          vim.lsp.util.apply_workspace_edit(r.edit, enc)
  --        end
  --      end
  --    end
  --    vim.lsp.buf.format({async = false})
  --  end
  --})
else
  vim.notify("gopls is not installed", vim.log.levels.WARN, { title = "Nvim-config" })
end

-- Rust support
if utils.executable('rust-analyzer') then
  vim.g.rustaceanvim = {
    -- Plugin configuration
    tools = {
    },
    -- LSP configuration
    server = {
      on_attach = custom_attach,
      --on_attach = function(client, bufnr)
      --  -- you can also put keymaps in here
      --end,
      default_settings = {
        -- rust-analyzer language server configuration
        ['rust-analyzer'] = {
          compltion = {
            addCallArgumentSnippets = false,
            addCallParenthesis = false,
          },
        },
      },
    },
    -- DAP configuration
    dap = {
    },
  }
  --lspconfig.rust_analyzer.setup {
  --  on_attach = custom_attach,
  --  capabilities = capabilities,
  --  settings = {
  --    ['rust-analyzer'] = {},
  --  },
  --}
else
  vim.notify("Rust Analyzer is not installed", vim.log.levels.WARN, { title = "Nvim-config" })
end

-- if utils.executable('pyright') then
--   lspconfig.pyright.setup{
--     on_attach = custom_attach,
--     capabilities = capabilities
--   }
-- else
--   vim.notify("pyright not found!", vim.log.levels.WARN, {title = 'Nvim-config'})
-- end

if utils.executable("ltex-ls") then
  lspconfig.ltex.setup {
    on_attach = custom_attach,
    cmd = { "ltex-ls" },
    filetypes = { "text", "plaintex", "tex", "markdown" },
    settings = {
      ltex = {
        language = "en"
      },
    },
    flags = { debounce_text_changes = 300 },
}
end

if utils.executable("clangd") then
  lspconfig.clangd.setup {
    on_attach = custom_attach,
    capabilities = capabilities,
    filetypes = { "c", "cpp", "cc" },
    flags = {
      debounce_text_changes = 500,
    },
  }
end

-- set up vim-language-server
if utils.executable("vim-language-server") then
  lspconfig.vimls.setup {
    on_attach = custom_attach,
    flags = {
      debounce_text_changes = 500,
    },
    capabilities = capabilities,
  }
else
  vim.notify("vim-language-server not found!", vim.log.levels.WARN, { title = "Nvim-config" })
end

-- set up bash-language-server
if utils.executable("bash-language-server") then
  lspconfig.bashls.setup {
    on_attach = custom_attach,
    capabilities = capabilities,
  }
end

if utils.executable("lua-language-server") then
  -- settings for lua-language-server can be found on https://github.com/LuaLS/lua-language-server/wiki/Settings .
  lspconfig.lua_ls.setup {
    on_attach = custom_attach,
    settings = {
      Lua = {
        runtime = {
          -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
          version = "LuaJIT",
        },
      },
    },
    capabilities = capabilities,
  }
end

-- Change diagnostic signs.
fn.sign_define("DiagnosticSignError", { text = '🆇', texthl = "DiagnosticSignError" })
fn.sign_define("DiagnosticSignWarn", { text = '⚠️', texthl = "DiagnosticSignWarn" })
fn.sign_define("DiagnosticSignInfo", { text = 'ℹ️', texthl = "DiagnosticSignInfo" })
fn.sign_define("DiagnosticSignHint", { text = '', texthl = "DiagnosticSignHint" })
-- fn.sign_define("DiagnosticSignError", { text = '✗', texthl = "DiagnosticSignError" })
-- fn.sign_define("DiagnosticSignWarn", { text = '⚠', texthl = "DiagnosticSignWarn" })
-- fn.sign_define("DiagnosticSignInfo", { text = 'ℹ', texthl = "DiagnosticSignInfo" })
-- fn.sign_define("DiagnosticSignHint", { text = '💡', texthl = "DiagnosticSignHint" })

-- global config for diagnostic
diagnostic.config {
  underline = false,
  virtual_text = false,
  signs = true,
  severity_sort = true,
}

-- lsp.handlers["textDocument/publishDiagnostics"] = lsp.with(lsp.diagnostic.on_publish_diagnostics, {
--   underline = false,
--   virtual_text = false,
--   signs = true,
--   update_in_insert = false,
-- })

-- Change border of documentation hover window, See https://github.com/neovim/neovim/pull/13998.
lsp.handlers["textDocument/hover"] = lsp.with(vim.lsp.handlers.hover, {
  border = "rounded",
})
