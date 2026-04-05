vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.syntax = "on"
vim.cmd.colorscheme("habamax")
vim.api.nvim_set_hl(0, "Normal", { bg = "#000000" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "#000000" })


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

vim.api.nvim_set_hl(0, "StMode_Normal",   { fg = "#000000", bg = "#7c8f8f", bold = true })
vim.api.nvim_set_hl(0, "StMode_Insert",   { fg = "#000000", bg = "#6a9955", bold = true })
vim.api.nvim_set_hl(0, "StMode_Visual",   { fg = "#000000", bg = "#c586c0", bold = true })
vim.api.nvim_set_hl(0, "StMode_Command",  { fg = "#000000", bg = "#ce9178", bold = true })
vim.api.nvim_set_hl(0, "StMode_Replace",  { fg = "#000000", bg = "#d16969", bold = true })
vim.api.nvim_set_hl(0, "StMode_Terminal", { fg = "#000000", bg = "#569cd6", bold = true })
vim.api.nvim_set_hl(0, "StFile",          { fg = "#d4d4d4", bg = "#1e1e1e" })
vim.api.nvim_set_hl(0, "StFileMod",       { fg = "#ce9178", bg = "#1e1e1e" })
vim.api.nvim_set_hl(0, "StMid",           { fg = "#808080", bg = "#0a0a0a" })
vim.api.nvim_set_hl(0, "StRight",         { fg = "#808080", bg = "#1e1e1e" })
vim.api.nvim_set_hl(0, "StPos",           { fg = "#d4d4d4", bg = "#1e1e1e", bold = true })

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
