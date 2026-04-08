vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.syntax = "on"
vim.cmd.colorscheme("habamax")
vim.api.nvim_set_hl(0, "Normal", { bg = "#0e0d0a" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "#13120e" })


-- Statusline

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

function Statusline()
  local mode_key = vim.api.nvim_get_mode().mode:sub(1, 1)
  if mode_key == "\22" then mode_key = "\22" end
  local mode = mode_map[mode_key] or mode_map["n"]

  local filename = vim.fn.expand("%:t")
  if filename == "" then filename = "[No Name]" end
  local modified = vim.bo.modified and " +" or ""

  local ft = vim.bo.filetype ~= "" and vim.bo.filetype or "plain"
  local ln = vim.fn.line(".")
  local col = vim.fn.col(".")
  local pct = math.floor(vim.fn.line(".") / math.max(vim.fn.line("$"), 1) * 100)

  return table.concat({
    "%#" .. mode.hl .. "#", mode.text,
    "%#StFile#", " ", filename,
    "%#StFileMod#", modified,
    "%#StMid#", " ", branch_cache, "%=",
    "%#StRight#", ft, " ",
    "%#StPos#", " ", ln, ":", col, " ", pct, "%% ",
  })
end

vim.opt.statusline = "%!v:lua.Statusline()"
