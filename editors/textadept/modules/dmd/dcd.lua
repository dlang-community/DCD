local M = {}

M.PATH_TO_DCD_CLIENT = "dcd-client"

local calltips = {}
local currentCalltip = 1

function M.registerImages()
	buffer:register_image(1, M.FIELD)
	buffer:register_image(2, M.FUNCTION)
	buffer:register_image(3, M.PACKAGE)
	buffer:register_image(4, M.MODULE)
	buffer:register_image(5, M.KEYWORD)
	buffer:register_image(6, M.CLASS)
	buffer:register_image(7, M.UNION)
	buffer:register_image(8, M.STRUCT)
	buffer:register_image(9, M.INTERFACE)
	buffer:register_image(10, M.ENUM)
	buffer:register_image(11, M.ALIAS)
end

local function showCompletionList(r)
	M.registerImages()
	local setting = buffer.auto_c_choose_single
	buffer.auto_c_choose_single = false;
	buffer.auto_c_max_width = 0
	local completions = {}
	for symbol, kind in r:gmatch("([^%s]+)\t(%a)\n") do
		completion = symbol
		if kind == "k" then
			completion = completion .. "?5"
		elseif kind == "v" then
			completion = completion .. "?1"
		elseif kind == "e" then
			completion = completion .. "?10"
		elseif kind == "s" then
			completion = completion .. "?8"
		elseif kind == "g" then
			completion = completion .. "?10"
		elseif kind == "u" then
			completion = completion .. "?7"
		elseif kind == "m" then
			completion = completion .. "?1"
		elseif kind == "c" then
			completion = completion .. "?6"
		elseif kind == "i" then
			completion = completion .. "?9"
		elseif kind == "f" then
			completion = completion .. "?2"
		elseif kind == "M" then
			completion = completion .. "?4"
		elseif kind == "P" then
			completion = completion .. "?3"
		elseif kind == "l" then
			completion = completion .. "?11"
		end
		completions[#completions + 1] = completion
	end
	table.sort(completions, function(a, b) return string.upper(a) < string.upper(b) end)
	local charactersEntered = buffer.current_pos - buffer:word_start_position(buffer.current_pos)
	if buffer.char_at[buffer.current_pos - 1] == string.byte('.')
			or buffer.char_at[buffer.current_pos - 1] == string.byte('(') then
		charactersEntered = 0
	end
	buffer:auto_c_show(charactersEntered, table.concat(completions, " "))
	--buffer.auto_c_fill_ups = "(.["
	buffer.auto_c_choose_single = setting
end


local function showCurrentCallTip()
	local tip = calltips[currentCalltip]
	buffer:call_tip_show(buffer:word_start_position(buffer.current_pos),
		string.format("%d of %d\1\2\n%s", currentCalltip, #calltips,
			calltips[currentCalltip]))
end

local function showCalltips(calltip)
	currentCalltip = 1
	calltips = {}
	for tip in calltip:gmatch("(.-)\n") do
		if tip ~= "calltips" then
			table.insert(calltips, tip)
		end
	end
	if (#calltips > 0) then
		showCurrentCallTip()
	end
end

function M.cycleCalltips(delta)
	if not buffer:call_tip_active() then
		return false
	end
	if delta > 0 then
		currentCalltip = math.max(math.min(#calltips, currentCalltip + 1), 1)
	else
		currentCalltip = math.min(math.max(1, currentCalltip - 1), #calltips)
	end
	showCurrentCallTip()
end

function M.gotoDeclaration()
	local fileName = os.tmpname()
	local command = M.PATH_TO_DCD_CLIENT .. " -l -c" .. buffer.current_pos .. " > " .. fileName
	local mode = "w"
	if _G.WIN32 then
		mode = "wb"
	end
	local p = io.popen(command, mode)
	p:write(buffer:get_text())
	p:flush()
	p:close()
	local tmpFile = io.open(fileName, "r")
	local r = tmpFile:read("*a")
	if r ~= "\n" then
		-- TODO: Go to declaration
	end
	os.remove(fileName)
end

events.connect(events.CALL_TIP_CLICK, function(arrow)
	if buffer:get_lexer() ~= "dmd" then return end
	if arrow == 1 then
		M.cycleCalltips(-1)
	elseif arrow == 2 then
		M.cycleCalltips(1)
	end
end)

function M.autocomplete(ch)
	if buffer:get_lexer() ~= "dmd" then return end
	local fileName = os.tmpname()
	local command = M.PATH_TO_DCD_CLIENT .. " -c" .. buffer.current_pos .. " > " .. fileName
	local mode = "w"
	if _G.WIN32 then
		mode = "wb"
	end
	local p = io.popen(command, mode)
	p:write(buffer:get_text())
	p:flush()
	p:close()
	local tmpFile = io.open(fileName, "r")
	local r = tmpFile:read("*a")
	if r ~= "\n" then
		if r:match("^identifiers.*") then
			showCompletionList(r)
		else
			showCalltips(r)
		end
	end
	os.remove(fileName)
end

M.ALIAS =[[
/* XPM */
static char * alias_xpm[] = {
"16 16 17 1",
" 	c None",
".	c #547AA0",
"+	c #547BA2",
"@	c #547CA4",
"#	c #F0F0F0",
"$	c #547DA6",
"%	c #F5F5F5",
"&	c #547EA8",
"*	c #FBFBFB",
"=	c #F7F7F7",
"-	c #F2F2F2",
";	c #547BA3",
">	c #ECECEC",
",	c #547AA1",
"'	c #E7E7E7",
")	c #54799F",
"!	c #54789D",
"                ",
"                ",
"   ..........   ",
"  ++++++++++++  ",
"  @@@@@##@@@@@  ",
"  $$$$%%%%$$$$  ",
"  &&&&****&&&&  ",
"  &&&==&&==&&&  ",
"  $$$==$$==$$$  ",
"  @@@------@@@  ",
"  ;;>>>>>>>>;;  ",
"  ,,'',,,,'',,  ",
"  ))))))))))))  ",
"   !!!!!!!!!!   ",
"                ",
"                "};
]]

-- union icon
M.UNION = [[
/* XPM */
static char * union_xpm[] = {
"16 16 18 1",
" 	c None",
".	c #A06B35",
"+	c #A87038",
"@	c #AC7339",
"#	c #F7EFE7",
"$	c #AF753A",
"%	c #F9F4EE",
"&	c #B3783C",
"*	c #FCFAF7",
"=	c #FDFBF8",
"-	c #B1763B",
";	c #FAF5F0",
">	c #F8F1EA",
",	c #A97138",
"'	c #F4EBE1",
")	c #A36D36",
"!	c #F2E6D9",
"~	c #9C6833",
"                ",
"                ",
"   ..........   ",
"  ++++++++++++  ",
"  @@##@@@@##@@  ",
"  $$%%$$$$%%$$  ",
"  &&**&&&&**&&  ",
"  &&==&&&&==&&  ",
"  --;;----;;--  ",
"  @@>>@@@@>>@@  ",
"  ,,'''''''',,  ",
"  )))!!!!!!)))  ",
"  ............  ",
"   ~~~~~~~~~~   ",
"                ",
"                "};
]]

-- class icon
M.CLASS = [[
/* XPM */
static char * class_xpm[] = {
"16 16 18 1",
" 	c None",
".	c #006AD6",
"+	c #006DDC",
"@	c #0070E2",
"#	c #F0F0F0",
"$	c #0072E6",
"%	c #F5F5F5",
"&	c #0075EC",
"*	c #FBFBFB",
"=	c #F7F7F7",
"-	c #0073E8",
";	c #F2F2F2",
">	c #006EDE",
",	c #ECECEC",
"'	c #006BD8",
")	c #E7E7E7",
"!	c #0069D4",
"~	c #0066CE",
"                ",
"                ",
"   ..........   ",
"  ++++++++++++  ",
"  @@@@#####@@@  ",
"  $$$%%%%%%%$$  ",
"  &&***&&&**&&  ",
"  &&==&&&&&&&&  ",
"  --==--------  ",
"  @@;;;@@@;;@@  ",
"  >>>,,,,,,,>>  ",
"  '''')))))'''  ",
"  !!!!!!!!!!!!  ",
"   ~~~~~~~~~~   ",
"                ",
"                "};
]]


-- interface icon
M.INTERFACE = [[
/* XPM */
static char * interface_xpm[] = {
"16 16 19 1",
" 	c None",
".	c #CC7729",
"+	c #D47D2D",
"@	c #D58032",
"#	c #F0F0F0",
"$	c #D58134",
"%	c #FFFFFF",
"&	c #F5F5F5",
"*	c #D6853B",
"=	c #FBFBFB",
"-	c #FDFDFD",
";	c #D58236",
">	c #F7F7F7",
",	c #F2F2F2",
"'	c #ECECEC",
")	c #CF792A",
"!	c #E7E7E7",
"~	c #CA7629",
"{	c #C37228",
"                ",
"                ",
"   ..........   ",
"  ++++++++++++  ",
"  @@@######@@@  ",
"  $$$%&&&&&$$$  ",
"  *****==*****  ",
"  *****--*****  ",
"  ;;;;;>>;;;;;  ",
"  @@@@@,,@@@@@  ",
"  +++''''''+++  ",
"  )))!!!!!!)))  ",
"  ~~~~~~~~~~~~  ",
"   {{{{{{{{{{   ",
"                ",
"                "};
]]

-- struct icon
M.STRUCT = [[
/* XPM */
static char * struct_xpm[] = {
"16 16 19 1",
" 	c None",
".	c #000098",
"+	c #00009E",
"@	c #0000A2",
"#	c #F0F0F0",
"$	c #0000A4",
"%	c #F5F5F5",
"&	c #FFFFFF",
"*	c #0000A8",
"=	c #FBFBFB",
"-	c #FDFDFD",
";	c #0000A6",
">	c #F7F7F7",
",	c #F2F2F2",
"'	c #ECECEC",
")	c #00009A",
"!	c #E7E7E7",
"~	c #000096",
"{	c #000092",
"                ",
"                ",
"   ..........   ",
"  ++++++++++++  ",
"  @@@#######@@  ",
"  $$%&%%%%%%$$  ",
"  **===*******  ",
"  **-------***  ",
"  ;;;>>>>>>>;;  ",
"  @@@@@@@,,,@@  ",
"  ++''''''''++  ",
"  ))!!!!!!!)))  ",
"  ~~~~~~~~~~~~  ",
"   {{{{{{{{{{   ",
"                ",
"                "};
]]

-- functions icon
M.FUNCTION = [[
/* XPM */
static char * function_xpm[] = {
"16 16 17 1",
" 	c None",
".	c #317025",
"+	c #367B28",
"@	c #387F2A",
"#	c #F0F0F0",
"$	c #FFFFFF",
"%	c #F5F5F5",
"&	c #3A832C",
"*	c #FBFBFB",
"=	c #FDFDFD",
"-	c #F7F7F7",
";	c #F2F2F2",
">	c #ECECEC",
",	c #347627",
"'	c #E7E7E7",
")	c #306D24",
"!	c #2F6A23",
"                ",
"                ",
"   ..........   ",
"  ++++++++++++  ",
"  @@@######@@@  ",
"  @@@$%%%%%@@@  ",
"  &&&**&&&&&&&  ",
"  &&&=====&&&&  ",
"  @@@-----@@@@  ",
"  @@@;;@@@@@@@  ",
"  +++>>+++++++  ",
"  ,,,'',,,,,,,  ",
"  ))))))))))))  ",
"   !!!!!!!!!!   ",
"                ",
"                "};
]]

-- fields icon
M.FIELD = [[
/* XPM */
static char * variable_xpm[] = {
"16 16 18 1",
" 	c None",
".	c #933093",
"+	c #A035A0",
"@	c #A537A5",
"#	c #FFFFFF",
"$	c #F0F0F0",
"%	c #A637A6",
"&	c #F5F5F5",
"*	c #AC39AC",
"=	c #FBFBFB",
"-	c #FDFDFD",
";	c #F7F7F7",
">	c #F2F2F2",
",	c #ECECEC",
"'	c #9A339A",
")	c #E7E7E7",
"!	c #8E2F8E",
"~	c #8B2E8B",
"                ",
"                ",
"   ..........   ",
"  ++++++++++++  ",
"  @@#$@@@@$$@@  ",
"  %%&#%%%%&&%%  ",
"  **==****==**  ",
"  ***--**--***  ",
"  %%%;;%%;;%%%  ",
"  @@@@>>>>@@@@  ",
"  ++++,,,,++++  ",
"  '''''))'''''  ",
"  !!!!!!!!!!!!  ",
"   ~~~~~~~~~~   ",
"                ",
"                "};
]]

--package icon
M.PACKAGE = [[
/* XPM */
static char * package_xpm[] = {
"16 16 6 1",
" 	c None",
".	c #000100",
"+	c #050777",
"@	c #242BAE",
"#	c #2E36BF",
"$	c #434FE5",
"                ",
"  ............  ",
" .$$$$$$$$$$$$. ",
" .$##@@+$##@@+. ",
" .$#@@@+$#@@@+. ",
" .$@@@#+$@@@#+. ",
" .$@@##+$@@##+. ",
" .$+++++$+++++. ",
" .$$$$$$$$$$$$. ",
" .$##@@+$##@@+. ",
" .$#@@@+$#@@@+. ",
" .$@@@#+$@@@#+. ",
" .$@@##+$@@##+. ",
" .$+++++$+++++. ",
"  ............  ",
"                "};
]]

-- module icon
M.MODULE = [[
/* XPM */
static char * module_xpm[] = {
"16 16 14 1",
" 	c None",
".	c #000000",
"+	c #000100",
"@	c #FFFF83",
"#	c #FFFF00",
"$	c #FFFF28",
"%	c #FFFF6A",
"&	c #FFFF4C",
"*	c #D5D500",
"=	c #CDCD00",
"-	c #A3A300",
";	c #B2B200",
">	c #C3C300",
",	c #919100",
"                ",
"       .+       ",
"      .@#+      ",
"      .@#+      ",
"     .$@##+     ",
"    ..%@##++    ",
"  ..&%%@####++  ",
" .@@@@@%######+ ",
" +*****=-;;;;;+ ",
"  ++>==*;--,..  ",
"    ++=*;-..    ",
"     +>*;,.     ",
"      +*;.      ",
"      +*;.      ",
"       ++       ",
"                "};
]]

M.ENUM = [[
/* XPM */
static char * enum_dec_xpm[] = {
"16 16 18 1",
" 	c None",
".	c #6D43C0",
"+	c #754EC3",
"@	c #7751C4",
"#	c #F0F0F0",
"$	c #7852C5",
"%	c #FFFFFF",
"&	c #F5F5F5",
"*	c #7D58C7",
"=	c #FBFBFB",
"-	c #FDFDFD",
";	c #F7F7F7",
">	c #F2F2F2",
",	c #ECECEC",
"'	c #7048C2",
")	c #E7E7E7",
"!	c #6A40BF",
"~	c #673EBA",
"                ",
"                ",
"   ..........   ",
"  ++++++++++++  ",
"  @@@######@@@  ",
"  $$$%&&&&&$$$  ",
"  ***==*******  ",
"  ***-----****  ",
"  $$$;;;;;$$$$  ",
"  @@@>>@@@@@@@  ",
"  +++,,,,,,+++  ",
"  '''))))))'''  ",
"  !!!!!!!!!!!!  ",
"   ~~~~~~~~~~   ",
"                ",
"                "};
]]

-- keyword icon
M.KEYWORD = [[
/* XPM */
static char * keyword_xpm[] = {
"16 16 24 1",
" 	c None",
".	c #B91C1C",
"+	c #BA1C1C",
"@	c #BE1D1D",
"#	c #C31E1E",
"$	c #C21E1E",
"%	c #F0F0F0",
"&	c #C71E1E",
"*	c #F5F5F5",
"=	c #CC1F1F",
"-	c #FBFBFB",
";	c #CB1F1F",
">	c #CD1F1F",
",	c #FDFDFD",
"'	c #C91F1F",
")	c #F7F7F7",
"!	c #C41E1E",
"~	c #F2F2F2",
"{	c #C01D1D",
"q	c #ECECEC",
"^	c #BB1D1D",
"/	c #E7E7E7",
"(	c #B71C1C",
"_	c #B21B1B",
"                ",
"                ",
"   ..........   ",
"  @@@@@@@@@@@@  ",
"  #$%%%%%%$$#$  ",
"  &&*******&&&  ",
"  ==--==;---==  ",
"  >>,,>>>>,,>>  ",
"  ''))''''))''  ",
"  !!~~!!!~~~!!  ",
"  {{qqqqqqq{{{  ",
"  ^^//////^^^^  ",
"  ((((((((((((  ",
"   __________   ",
"                ",
"                "};
]]

return M
