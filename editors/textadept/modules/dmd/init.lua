local M = {}

local dcd = require "dmd.dcd"

if type(_G.snippets) == 'table' then
  _G.snippets.dmd = {}
end

if type(_G.keys) == 'table' then
  _G.keys.dmd = {}
end

events.connect(events.CHAR_ADDED, function(ch)
	if string.char(ch) == '(' or string.char(ch) == '.' or string.char(ch) == '[' then
		dcd.autocomplete()
	end
end)

local function autocomplete()
	dcd.registerImages()
	dcd.autocomplete()
	if not buffer:auto_c_active() then
		textadept.editing.autocomplete("word")
	end
end

-- D-specific key commands.
keys.dmd = {
	[keys.LANGUAGE_MODULE_PREFIX] = {
		m = { io.open_file,
		(_USERHOME..'/modules/dmd/init.lua'):iconv('UTF-8', _CHARSET) },
	},
	['c\n'] = {autocomplete},
	['ch'] = {dcd.showDoc},
	['cG'] = {dcd.gotoDeclaration},
	['down'] = {dcd.cycleCalltips, 1},
	['up'] = {dcd.cycleCalltips, -1},
}

function M.set_buffer_properties()
end

return M
