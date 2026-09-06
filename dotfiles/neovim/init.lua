vim.opt.termguicolors = true
vim.opt.background = "dark"
vim.opt.number = true
vim.opt.syntax = "on"
vim.cmd.colorscheme("habamax")
vim.api.nvim_set_hl(0, "Normal", { bg = "#0e0d0a" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "#13120e" })

-- netrw claims directory buffers on startup, and the tree below replaces it.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.opt.mouse = "a"


vim.opt.laststatus = 2
vim.opt.showmode = false

local mode_map = {
  ["n"]  = { text = " NORMAL ",  hl = "StMode_Normal" },
  ["i"]  = { text = " INSERT ",  hl = "StMode_Insert" },
  ["v"]  = { text = " VISUAL ",  hl = "StMode_Visual" },
  ["V"]  = { text = " V-LINE ",  hl = "StMode_Visual" },
  ["\22"] = { text = " V-BLOCK ", hl = "StMode_Visual" },
  ["c"]  = { text = " COMMAND ", hl = "StMode_Command" },
  ["R"]  = { text = " REPLACE ", hl = "StMode_Replace" },
  ["t"]  = { text = " TERMINAL ", hl = "StMode_Terminal" },
}

vim.api.nvim_set_hl(0, "StMode_Normal",   { fg = "#0e0d0a", bg = "#6b9e78", bold = true })
vim.api.nvim_set_hl(0, "StMode_Insert",   { fg = "#0e0d0a", bg = "#c9a84c", bold = true })
vim.api.nvim_set_hl(0, "StMode_Visual",   { fg = "#0e0d0a", bg = "#7eaab8", bold = true })
vim.api.nvim_set_hl(0, "StMode_Command",  { fg = "#0e0d0a", bg = "#c47055", bold = true })
vim.api.nvim_set_hl(0, "StMode_Replace",  { fg = "#0e0d0a", bg = "#c47055", bold = true })
vim.api.nvim_set_hl(0, "StMode_Terminal", { fg = "#0e0d0a", bg = "#7eaab8", bold = true })
vim.api.nvim_set_hl(0, "StFile",          { fg = "#ddd7cd", bg = "#13120e" })
vim.api.nvim_set_hl(0, "StFileMod",       { fg = "#c9a84c", bg = "#13120e" })
vim.api.nvim_set_hl(0, "StMid",           { fg = "#665f56", bg = "#0e0d0a" })
vim.api.nvim_set_hl(0, "StRight",         { fg = "#a09890", bg = "#13120e" })
vim.api.nvim_set_hl(0, "StPos",           { fg = "#ddd7cd", bg = "#13120e", bold = true })
vim.api.nvim_set_hl(0, "StHintKey",       { fg = "#c9a84c", bg = "#0e0d0a", bold = true })

-- The tree puts its own key bar in the tabline once it is open, so this only
-- has to cover the closed case.
local function tree_hint()
  local ok, api = pcall(require, "nvim-tree.api")
  if not ok or api.tree.is_visible() then return "" end
  return "  %#StHintKey#F2 %#StMid#files  %#StHintKey#F3 %#StMid#reveal"
end

local function git_branch()
  local branch = vim.fn.system("git -C " .. vim.fn.expand("%:p:h") .. " rev-parse --abbrev-ref HEAD 2>/dev/null")
  if vim.v.shell_error ~= 0 then return "" end
  return " " .. branch:gsub("%s+", "")
end

local branch_cache = ""
local branch_timer = (vim.uv or vim.loop).new_timer()
branch_timer:start(0, 5000, vim.schedule_wrap(function()
  branch_cache = git_branch()
end))

-- A `%!` statusline is evaluated against the current window whichever window is
-- being drawn, so with the tree open every split would report the tree. The
-- window being drawn is in v:statusline_winid.
function Statusline()
  local win = vim.g.statusline_winid
  if not win or not vim.api.nvim_win_is_valid(win) then
    win = vim.api.nvim_get_current_win()
  end
  local buf = vim.api.nvim_win_get_buf(win)

  local mode_key = vim.api.nvim_get_mode().mode:sub(1, 1)
  local mode = mode_map[mode_key] or mode_map["n"]

  local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
  if filename == "" then filename = "[No Name]" end
  local modified = vim.bo[buf].modified and " +" or ""

  local ft = vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "plain"
  local cursor = vim.api.nvim_win_get_cursor(win)
  local ln, col = cursor[1], cursor[2] + 1
  local pct = math.floor(ln / math.max(vim.api.nvim_buf_line_count(buf), 1) * 100)

  return table.concat({
    "%#" .. mode.hl .. "#", mode.text,
    "%#StFile#", " ", filename,
    "%#StFileMod#", modified,
    "%#StMid#", " ", branch_cache, tree_hint(), "%=",
    "%#StRight#", ft, " ",
    "%#StPos#", " ", ln, ":", col, " ", pct, "%% ",
  })
end

vim.opt.statusline = "%!v:lua.Statusline()"


vim.opt.list = true
vim.opt.listchars = { tab = "→ ", trail = "·", nbsp = "␣", extends = "»", precedes = "«" }
vim.api.nvim_set_hl(0, "Whitespace", { fg = "#3a352e" })
vim.api.nvim_set_hl(0, "NonText", { fg = "#3a352e" })

vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4


local tree_ok, tree = pcall(require, "nvim-tree")

if tree_ok then
  local api = require("nvim-tree.api")

  tree.setup({
    view = { width = 32, signcolumn = "no" },
    -- Everything shows except the contents of .git, which is thousands of files
    -- nobody opens. `H` and `I` put the two filters back.
    filters = { dotfiles = false, git_ignored = false, custom = { "^\\.git$" } },
    renderer = {
      group_empty = true,
      indent_markers = { enable = true },
      root_folder_label = ":t",
      icons = {
        show = { file = false, folder = true, folder_arrow = false, git = true },
        glyphs = {
          folder = {
            default = "▸", open = "▾",
            empty = "▸", empty_open = "▾",
            symlink = "▸", symlink_open = "▾",
          },
          git = {
            unstaged = "*", staged = "+", unmerged = "!", renamed = ">",
            untracked = "?", deleted = "x", ignored = "-",
          },
        },
      },
    },
    actions = { open_file = { window_picker = { enable = false } } },
    on_attach = function(bufnr)
      api.map.on_attach.default(bufnr)

      local function map(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { buffer = bufnr, silent = true, nowait = true, desc = desc })
      end

      -- A click moves the cursor before the release fires, so by then the row
      -- under the cursor is the row that was clicked.
      map("<LeftRelease>", function()
        if api.tree.get_node_under_cursor() then api.node.open.edit() end
      end, "Open")
      map("?", api.tree.toggle_help, "Help")
      map("<F2>", api.tree.close, "Close")
    end,
  })

  -- The sidebar is too narrow for the real statusline to say anything useful.
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    pattern = "NvimTree_*",
    callback = function()
      vim.wo.statusline = "%#StMode_Normal# FILES %#StMid#"
    end,
  })

  vim.api.nvim_set_hl(0, "TreeKey",     { fg = "#c9a84c", bg = "#13120e", bold = true })
  vim.api.nvim_set_hl(0, "TreeDesc",    { fg = "#a09890", bg = "#13120e" })
  vim.api.nvim_set_hl(0, "TabLineFill", { bg = "#13120e" })

  local function keybar(keys)
    local bar = { "%#TreeDesc# " }
    for _, k in ipairs(keys) do
      bar[#bar + 1] = "%#TreeKey#" .. k[1] .. " %#TreeDesc#" .. k[2] .. "   "
    end
    return table.concat(bar)
  end

  local tree_keys = keybar({
    { "click", "open" }, { "F2", "close" }, { "a", "new" }, { "r", "rename" },
    { "d", "delete" }, { "x/c/p", "cut copy paste" }, { "H/I", "filters" },
    { "?", "all keys" },
  })
  local file_keys = keybar({
    { "F2", "back to the tree" }, { "F3", "reveal this file" },
  })

  -- A `%!` tabline is evaluated against the focused window, which is what tells
  -- these two apart.
  function TreeKeyBar()
    return vim.bo.filetype == "NvimTree" and tree_keys or file_keys
  end

  -- The tabline is the only full width strip nvim has, so it carries the key
  -- list rather than tabs, and real tabs will not show while the tree is open.
  vim.opt.tabline = "%!v:lua.TreeKeyBar()"
  vim.opt.showtabline = 0
  api.events.subscribe(api.events.Event.TreeOpen, function() vim.opt.showtabline = 2 end)
  api.events.subscribe(api.events.Event.TreeClose, function() vim.opt.showtabline = 0 end)

  -- One key for the whole sidebar, so F2 from a file means go there rather than
  -- close it. The buffer local F2 inside the tree is what closes it.
  vim.keymap.set("n", "<F2>", function()
    if api.tree.is_visible() then
      api.tree.focus()
    else
      api.tree.open()
    end
  end, { silent = true, desc = "Files" })
  vim.keymap.set("n", "<F3>", function()
    api.tree.find_file({ open = true, focus = true })
  end, { silent = true, desc = "Reveal file in tree" })
end
