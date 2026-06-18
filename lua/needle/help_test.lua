-- Tests for the help source's window/buffer restoration behavior.
--
-- Run from the repo root with:
--   nvim --headless -l lua/needle/help_test.lua -c 'qa!'
--
-- Drives the real picker UI: opens needle.help(), types a query, accepts the
-- selection, and inspects the resulting window layout. Exits 0 on success,
-- 1 on any failure.

vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local needle = require("needle")
needle.setup()

local pass, fail = 0, 0
local failures = {}
local function check(name, cond, detail)
  if cond then pass = pass + 1
  else fail = fail + 1; failures[#failures + 1] = { name = name, detail = detail } end
end

local function feed(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "tx", false)
end

-- Open the help picker, type a query that matches a builtin tag, and accept.
local function pick_help(query)
  needle.help()
  vim.wait(600)
  feed(query)
  vim.wait(400)
  feed("<CR>")
  vim.wait(600)
end

local function windows()
  local out = {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local b = api.nvim_win_get_buf(w)
    out[#out + 1] = {
      win = w, buf = b,
      name = api.nvim_buf_get_name(b),
      ft = api.nvim_get_option_value("filetype", { buf = b }),
      bt = api.nvim_get_option_value("buftype", { buf = b }),
    }
  end
  return out
end

local function find(wins, pred)
  for _, w in ipairs(wins) do if pred(w) then return w end end
end

local function reset()
  vim.cmd("silent! helpclose")
  vim.cmd("silent! only")
  vim.cmd("silent! enew")
  local keep = api.nvim_get_current_buf()
  for _, b in ipairs(api.nvim_list_bufs()) do
    if b ~= keep then pcall(api.nvim_buf_delete, b, { force = true }) end
  end
end

-- ----------------------------------------------------------------------------
-- Scenario B (run first, using the genuine initial scratch buffer): from a
-- fresh nvim with a single empty unnamed buffer, opening a help doc should
-- leave the help window plus the original empty scratch buffer underneath.
-- ----------------------------------------------------------------------------
do
  check("fresh: starts with one empty unnamed buffer",
    #api.nvim_tabpage_list_wins(0) == 1 and api.nvim_buf_get_name(0) == "",
    "expected a single unnamed window at startup")

  pick_help("help")
  local wins = windows()
  check("fresh: exactly two windows", #wins == 2,
    ("got %d windows"):format(#wins))
  check("fresh: a help window is shown",
    find(wins, function(w) return w.ft == "help" end) ~= nil, "no help window")
  local under = find(wins, function(w) return w.ft ~= "help" end)
  check("fresh: non-help window is the empty scratch, not the needle buffer",
    under ~= nil and under.ft ~= "needle" and under.name == "" and under.bt == "",
    under and ("ft=%s name='%s' bt=%s"):format(under.ft, under.name, under.bt) or "missing")
end

-- ----------------------------------------------------------------------------
-- Scenario A: from a single named buffer, opening a help doc should leave the
-- help window plus the original buffer underneath (not the needle buffer).
-- ----------------------------------------------------------------------------
reset()
do
  vim.cmd("edit /tmp/needle_help_test_a.txt")
  local orig_name = api.nvim_buf_get_name(0)
  check("single: one window before picking", #api.nvim_tabpage_list_wins(0) == 1)

  pick_help("help")
  local wins = windows()
  check("single: exactly two windows", #wins == 2,
    ("got %d windows"):format(#wins))
  check("single: a help window is shown",
    find(wins, function(w) return w.ft == "help" end) ~= nil, "no help window")
  local under = find(wins, function(w) return w.ft ~= "help" end)
  check("single: non-help window restores the original buffer",
    under ~= nil and under.name == orig_name,
    under and ("ft=%s name='%s'"):format(under.ft, under.name) or "missing")
end

io.stdout:write(("\n%d passed, %d failed\n"):format(pass, fail))
if fail > 0 then
  io.stdout:write("\nFailures:\n")
  for _, f in ipairs(failures) do
    io.stdout:write(("  - %s: %s\n"):format(f.name, f.detail or ""))
  end
  os.exit(1)
end
