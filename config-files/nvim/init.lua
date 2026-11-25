vim.o.number = true
vim.o.relativenumber = true
vim.o.signcolumn = "yes"
vim.o.winborder = "single"
vim.o.wrap = false
vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.softtabstop = 4
vim.o.clipboard = "unnamedplus"
vim.o.swapfile = false
vim.o.completeopt = "menu,menuone,noinsert,noselect"
vim.o.updatetime = 250
vim.g.mapleader = " "
vim.keymap.set('n', '<leader>o', ':update<CR> :source<CR>')
vim.keymap.set('n', '<leader>w', ':write<CR>')
vim.keymap.set('n', '<leader>q', ':quit<CR>')
vim.keymap.set('n', '<leader>lf', vim.lsp.buf.format)
vim.keymap.set('n', '<Esc>', '<cmd>noh<CR>', { silent = true })
vim.keymap.set('n', '<leader>n', '<cmd>tabnew<CR>', { desc = 'New tab' })
vim.keymap.set('n', '<leader>x', '<cmd>tabclose<CR>', { desc = 'Close tab' })
for i = 1, 9 do
  vim.keymap.set('n', '<leader>' .. i, '<cmd>tabnext ' .. i .. '<CR>', { desc = 'Go to tab ' .. i })
end
local tab_buf, closed_tabs = {}, {}

vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
  callback = function(ev)
    if vim.bo[ev.buf].buftype == "" then  -- real files only, not the run terminal
      tab_buf[vim.api.nvim_get_current_tabpage()] = ev.buf
    end
  end,
})

vim.api.nvim_create_autocmd("TabClosed", {
  callback = function()
    for tab, buf in pairs(tab_buf) do
      if not vim.api.nvim_tabpage_is_valid(tab) then
        table.insert(closed_tabs, buf)
        tab_buf[tab] = nil
      end
    end
  end,
})

vim.keymap.set("n", "<leader>u", function()
  local buf = table.remove(closed_tabs)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.cmd("tab sbuffer " .. buf)
  else
    vim.notify("No closed tab to reopen", vim.log.levels.INFO)
  end
end, { desc = "Reopen last closed tab" })
function _G.Tabline()
  local s = ""
  for i = 1, vim.fn.tabpagenr("$") do
    local buf = vim.fn.tabpagebuflist(i)[vim.fn.tabpagewinnr(i)]
    local name = vim.fn.fnamemodify(vim.fn.bufname(buf), ":t")
    if name == "" then name = "[No Name]" end
    s = s .. (i == vim.fn.tabpagenr() and "%#TabLineSel#" or "%#TabLine#")
          .. "%" .. i .. "T " .. i .. " " .. name:gsub("%%", "%%%%") .. " "
  end
  return s .. "%#TabLineFill#%T"
end
vim.o.tabline = "%!v:lua.Tabline()"
vim.g.closetag_filenames = '*.html,*.xhtml'
vim.pack.add({
		{src="https://github.com/nvim-lua/plenary.nvim"},
		{src="https://github.com/nvim-telescope/telescope.nvim"},
		{src="https://github.com/neovim/nvim-lspconfig"},
		{src="https://github.com/chomosuke/typst-preview.nvim"},
		{src="https://github.com/alvan/vim-closetag"},
		{src="https://github.com/uga-rosa/ccc.nvim"},
		{src="https://github.com/windwp/nvim-autopairs"}
})
require("nvim-autopairs").setup({})
require("ccc").setup({
	highlighter = { auto_enable = true, lsp = true },
})
vim.keymap.set('n', '<leader>cp', ":CccPick<CR>")
vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        if client and client:supports_method('textDocument/completion', ev.buf) then
            local chars = {}
            for i = 32, 126 do table.insert(chars, string.char(i)) end
            client.server_capabilities.completionProvider.triggerCharacters = chars
            vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
        end
    end,
})
vim.api.nvim_create_autocmd('CursorHold', {
    callback = function()
        vim.diagnostic.open_float(nil, { focusable = false })
    end,
})
vim.keymap.set('i', '<Tab>', function()
  if vim.fn.pumvisible() == 1 then
    if vim.fn.complete_info().selected == -1 then
      return '<C-n><C-y>' 
    else
      return '<C-y>'       
    end
  else
    return '<Tab>'
  end
end, { expr = true })

require "telescope".setup({})
local builtin = require("telescope.builtin")
vim.keymap.set('n', '<leader>f', builtin.find_files, {desc = 'Telescope find files'})
vim.keymap.set('n', '<leader>g', builtin.live_grep, {desc = 'Telescope live grep'})
vim.keymap.set('n', '<leader>h', builtin.help_tags, {desc = 'Telescope help tags'})
vim.keymap.set('n', '<leader>b', builtin.buffers, {desc = 'Telescope buffers'})


vim.keymap.set('n', '<leader>cd', ":Ex<CR>")
vim.lsp.enable({"lua_ls", "tinymist", "clangd", "emmet_language_server" })
local runners = {
	cpp  = "c++ -std=c++23 -Wall -Wextra -g {file} -o {out} && {out}",
	c    = "cc -std=c17 -Wall -Wextra -g {file} -o {out} && {out}",
	rust = "rustc {file} -o {out} && {out}",
	java   = "java {file}",
	python = "python3 {file}",
	julia  = "julia {file}",
	lua    = "lua {file}",
	sh     = "sh {file}",
}

-- vim.keymap.set("n", "<leader>r", function()
--   local cmd = runners[vim.bo.filetype]
--   if not cmd then
--     vim.notify("No runner for " .. vim.bo.filetype, vim.log.levels.WARN)
--     return
--   end
--
--   vim.cmd("write")
--   cmd = cmd:gsub("{file}", vim.fn.shellescape(vim.fn.expand("%:p")))
--          :gsub("{out}",  vim.fn.shellescape(vim.fn.expand("%:p:r")))
--    vim.cmd("botright 15split | terminal " .. cmd)
-- end, { desc = "Run current file" })

local run = { win = nil, buf = nil }

-- run `cmd` in a fresh terminal in the bottom pane (reused if still open)
local function term_run(cmd, cwd)
  local src_win = vim.api.nvim_get_current_win()

  if run.win and vim.api.nvim_win_is_valid(run.win) then
    vim.api.nvim_set_current_win(run.win)
  else
    vim.cmd("botright 15split")
    run.win = vim.api.nvim_get_current_win()
  end

  -- a terminal buffer runs one job, so swap in a fresh one and drop the old
  local old = run.buf
  run.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(run.win, run.buf)
  if old and vim.api.nvim_buf_is_valid(old) then
    vim.api.nvim_buf_delete(old, { force = true })  -- also kills a still-running job
  end

  vim.fn.jobstart(cmd, { term = true, cwd = cwd })
  vim.cmd("normal! G")  -- cursor on last line so the pane follows output

  vim.api.nvim_set_current_win(src_win)
end

-- what kind of project the current buffer is in, and its root
local function project()
  -- prefer the repo/flake root so a nested src/CMakeLists.txt isn't mistaken for the top
  local top = vim.fs.root(0, { ".git", "flake.nix" })
  if top and vim.uv.fs_stat(top .. "/CMakeLists.txt") then return "cmake", top end
  local root = vim.fs.root(0, "CMakeLists.txt")
  if root then return "cmake", root end
  root = vim.fs.root(0, "Makefile")
  if root then return "make", root end
end

-- wrap `cmd` so it runs inside the project's dev shell
local function in_env(root, cmd)
  if vim.fn.executable("direnv") == 1 and vim.uv.fs_stat(root .. "/.envrc") then
    return "direnv exec . sh -c " .. vim.fn.shellescape(cmd)
  elseif vim.uv.fs_stat(root .. "/flake.nix") then
    return "nix develop --command sh -c " .. vim.fn.shellescape(cmd)
  end
  return cmd
end

local cmake = { dir = "build", type = "Release" }

-- configure once (cmake --build re-runs it when CMakeLists change), then build everything
local function cmake_build()
  local d, j = cmake.dir, vim.uv.available_parallelism()
  return ("[ -f %s/CMakeCache.txt ] || cmake -S . -B %s -DCMAKE_BUILD_TYPE=%s -DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
          .. " && cmake --build %s -j %d"):format(d, d, cmake.type, d, j)
end

vim.keymap.set("n", "<leader>r", function()
  local kind, root = project()
  if kind == "cmake" then
    vim.cmd("wall")
    return term_run(in_env(root, cmake_build() .. " && cmake --build " .. cmake.dir .. " --target run"), root)
  elseif kind == "make" then
    vim.cmd("wall")
    return term_run(in_env(root, "make run"), root)
  end

  local cmd = runners[vim.bo.filetype]
  if not cmd then
    vim.notify("No runner for " .. vim.bo.filetype, vim.log.levels.WARN)
    return
  end
  vim.cmd("write")
  local file = vim.fn.shellescape(vim.fn.expand("%:p"))
  local out  = vim.fn.shellescape(vim.fn.expand("%:p:r"))
  cmd = cmd:gsub("{file}", function() return file end)
           :gsub("{out}",  function() return out end)
  term_run(cmd)
end, { desc = "Run project or current file" })

vim.keymap.set("n", "<leader>t", function()
  local kind, root = project()
  if kind ~= "cmake" then
    vim.notify("Not in a CMake project", vim.log.levels.WARN)
    return
  end
  vim.cmd("wall")
  local j = vim.uv.available_parallelism()
  term_run(in_env(root, cmake_build() .. (" && ctest --test-dir %s --output-on-failure -j %d"):format(cmake.dir, j)), root)
end, { desc = "Build and run CTest" })
