local M = {}

_M.dcd = require "dmd.dcd"

if type(_G.snippets) == 'table' then
  _G.snippets.dmd = {}
end

if type(_G.keys) == 'table' then
  _G.keys.dmd = {}
end

events.connect(events.CHAR_ADDED, function(ch)
	_M.dcd.autocomplete(ch)
end)

local function autocomplete()
	_M.dcd.registerImages()
	_M.dcd.autocomplete(string.byte('.'))
	if not buffer:auto_c_active() then
		_M.textadept.editing.autocomplete_word(keywords)
	end
end

-- D-specific key commands.
keys.dmd = {
	[keys.LANGUAGE_MODULE_PREFIX] = {
		m = { io.open_file,
		(_USERHOME..'/modules/dmd/init.lua'):iconv('UTF-8', _CHARSET) },
	},
	['c\n'] = {autocomplete},
	['down'] = {_M.dcd.cycleCalltips, 1},
	['up'] = {_M.dcd.cycleCalltips, -1},
}

function M.set_buffer_properties()
end

return M
