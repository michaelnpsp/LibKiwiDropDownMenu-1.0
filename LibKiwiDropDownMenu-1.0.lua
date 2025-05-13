-- Enhanced EasyMenu popup menu management code.

local lib = LibStub:NewLibrary("LibKiwiDropDownMenu-1.0", 1)
if not lib then return end

local _G = _G
local type = type
local pairs = pairs
local ipairs = ipairs
local tinsert = tinsert
local tremove = tremove

--------------------------------------------------------------------------------------------------
-- util functions
--------------------------------------------------------------------------------------------------

function lib:CopyTable(src, dst)
	if type(dst)~="table" then dst = {} end
	for k,v in pairs(src) do
		if type(v)=="table" then
			dst[k] = lib:CopyTable(v,dst[k])
		elseif dst[k]==nil then
			dst[k] = v
		end
	end
	return dst
end

--------------------------------------------------------------------------------------------------
-- menu library helper functions
--------------------------------------------------------------------------------------------------
do
	-- store unused tables to avoid generate garbage
	local tables = {}
	-- internal functions
	local function strfirstword(str)
		return strmatch(str, "^(.-) ") or str
	end
	-- insert menu
	function lib:insertMenu(src, dst, idx)
		idx = idx or #dst+1
		for i,item in ipairs(src) do
			table.insert(dst, idx+i-1, item)
		end
	end
	-- clear menu table, preserving special control fields
	function lib:wipeMenu(menu)
		local init = menu.init;	wipe(menu); menu.init = init
	end
	-- split a big menu items table in several submenus
	function lib:splitMenu(menu, fsort, fdisp, max)
		local count = #menu
		if count>1 then
			max = max or 28
			max = max>0 and math.ceil( count / math.ceil( count/max ) ) or -max
			fsort = fsort==nil and 'text' or fsort
			fdisp = fdisp or fsort or 'text'
			if fsort~=false then table.sort(menu, function(a,b) return a[fsort]<b[fsort] end ) 	end
			local items, first, last
			if count>max then
				for i=1,count do
					if not items or #items>=max then
						if items then
							menu[#menu].text = strfirstword(first[fdisp]) .. ' - ' .. strfirstword(last[fdisp])
						end
						items = {}
						tinsert(menu, { notCheckable = true, hasArrow = true, useParentValue = true, menuList = items } )
						first = menu[1]
					end
					last = tremove(menu,1)
					tinsert(items, last)
				end
				menu[#menu].text = strfirstword(first[fdisp]) .. ' - ' .. strfirstword(last[fdisp])
				menu._split = true
				return true
			end
		end
	end
	-- start menu definition
	function lib:defMenuStart(menu)
		local split = menu._split
		for _,item in ipairs(menu) do
			if split and item.menuList then
				for _,item in ipairs(item.menuList) do
					tables[#tables+1] = item; wipe(item)
				end
			end
			tables[#tables+1] = item; wipe(item)
		end
		lib:wipeMenu(menu)
		return menu
	end
	-- add an item to the menu
	function lib:defMenuAdd(menu, text, value, menuList)
		local item = tremove(tables) or {}
		item.text, item.value, item.notCheckable, item.menuList, item.hasArrow = text, value, true, menuList, (menuList~=nil) or nil
		menu[#menu+1] = item
		return item
	end
	-- end menu definition
	function lib:defMenuEnd(menu, text)
		if #menu==0 and text then
			menu[1] = tremove(tables) or {}
			menu[1].text, menu[1].notCheckable = text, true
		end
	end
	-- fill menu with checkbox items
	function lib:fillMenu(menu, items, set, checked, build)
		if type(items)~='table' then return end
		build = build or function(v) return v end
		for name, key in pairs(items) do
			local item = build( {text=name, value=key, isNotRadio=false, keepShownOnClick=1, func=set, checked=checked}, name, key )
			if item then menu[#menu+1] = item end
		end
		return menu
	end
	-- libSharedMedia data menus: mediaType = 'statusbar' | 'border' | 'sounds' | 'fonts'
	do
		local media
		local function init(menu, mediaType, set, checked, extra)
			media = media or LibStub("LibSharedMedia-3.0", true)
			lib:fillMenu(menu, extra, set, checked)
			lib:fillMenu(menu, media:HashTable(mediaType), set, checked)
			lib:splitMenu(menu)
			menu.init = nil -- do not call this init function anymore
		end
		function lib:defMediaMenu(mediaType, set, checked, extra)
			if type(checked)~='function' then
				extra, checked = checked, set
			end
			return { init = function(menu) init(menu, mediaType, set, checked, extra); end }
		end
	end
end

--------------------------------------------------------------------------------------------------
-- menu library main functions:
--   lib:showMenu(menuList, frameName, anchor, x, y, autoHideDelay)
--   lib:refreshMenu(element, hideChilds)
--   lib:getMenuValue(element)
--   lib:getMenuLevel(element)
--------------------------------------------------------------------------------------------------

do
	-- workaround for classic submenus bug, level 3 submenu only displays up to 8 items without this
	local FixClassicBug = select(4,GetBuildInfo())<90000 and function(level, count)
		local name = "DropDownList"..level
		local frame = _G[name]
		for index = 1, count do
			local button = _G[ name.."Button"..index ]
			if button and frame~=button:GetParent() then
				button:SetParent(frame)
			end
		end
	end or function() end
	-- color picker management
	local function picker_get_alpha()
		local a = ColorPickerFrame.SetupColorPickerAndShow and ColorPickerFrame:GetColorAlpha() or OpacitySliderFrame:GetValue()
		return WOW_PROJECT_ID~=WOW_PROJECT_MAINLINE and 1-a or a
	end
	local function picker_get_prev_color(c)
		local r, g, b, a
		if ColorPickerFrame.SetupColorPickerAndShow then
			r, g, b, a = ColorPickerFrame:GetPreviousValues()
		else
			r, g, b, a = c.r, c.g, c.b, c.opacity
		end
		return r, g, b, (WOW_PROJECT_ID~=WOW_PROJECT_MAINLINE and 1-a or a)
	end
	-- copy defaults
	local function copy_defaults(src, dst)
		for k,v in next, src do
			if dst[k]==nil then dst[k] = v; end
		end
	end
	-- menu initialization: special management of enhanced menuList tables, using fields not supported by the base UIDropDownMenu code.
	local function initialize( frame, level, menuList )
		if level then
			local menuValue = UIDROPDOWNMENU_MENU_VALUE
			local default = type(menuValue)=='table' and menuValue.__kwDefault
			frame.menuValues[level] = menuValue
			local init = menuList.init
			if init then -- custom initialization function for the menuList
				init(menuList, level, frame)
			end
			FixClassicBug(level, #menuList)
			for index=1,#menuList do
				local item = menuList[index]
				if default then copy_defaults(default, item) end
				if item.hidden==nil or not item.hidden(item) then
					if item.useParentValue then -- use the value of the parent popup, needed to make splitMenu() transparent
						item.value = UIDROPDOWNMENU_MENU_VALUE
					end
					if type(item.text)=='function' then -- save function text in another field for later use
						item.textf = item.text
					end
					if type(item.disabled)=='function' then
						item.disabledf = item.disabled
					end
					if item.disabledf then -- support for functions instead of only booleans
						item.disabled = item.disabledf(item, level, frame)
					end
					if item.textf then -- support for functions instead of only strings
						item.text = item.textf(item, level, frame)
					end
					if item.cf then -- cf replacing: checked & func
						item.func, item.checked, item.cf = item.cf, item.cf, nil
					end
					if item.isNotRadio == nil then
						item.notCheckable = true
					end
					if item.menuList then
						item.hasArrow = true
						if type(item.menuList)=='function' then item.menuList = item.menuList(frame, level) end
					end
					if item.default then -- default values for the child menuList
						item.value, item.default = {__kwDefault = item.default}, nil
					end
					if item.hasColorSwatch then -- simplified color management, only definition of get&set functions required to retrieve&save the color
						if not item.swatchFunc then
							local get, set = item.get, item.set
							item.swatchFunc  = function() local r,g,b,a = get(item); r,g,b = ColorPickerFrame:GetColorRGB(); set(item,r,g,b,a) end
							item.opacityFunc = function() local r,g,b = get(item); set(item,r,g,b,picker_get_alpha()); end
							item.cancelFunc = function(c) set(item, picker_get_prev_color(c)); end
						end
						item.r, item.g, item.b, item.opacity = item.get(item)
						item.opacity = 1 - item.opacity
					end
					item.index = index
					UIDropDownMenu_AddButton(item,level)
				end
			end
		end
	end
	-- get the MENU_LEVEL of the specified menu element ( element = DropDownList|button|nil )
	function lib:getMenuLevel(element)
		return element and ((element.dropdown and element:GetID()) or element:GetParent():GetID()) or UIDROPDOWNMENU_MENU_LEVEL
	end
	-- get the MENU_VALUE of the specified menu element ( element = level|DropDownList|button|nil )
	function lib:getMenuValue(element)
		return element and (UIDROPDOWNMENU_OPEN_MENU.menuValues[type(element)=='table' and self:getMenuLevel(element) or element]) or UIDROPDOWNMENU_MENU_VALUE
	end
	-- refresh a submenu ( element = level | button | dropdownlist )
	function lib:refreshMenu(element, hideChilds)
		local level = type(element)=='number' and element or self:getMenuLevel(element)
		if hideChilds then CloseDropDownMenus(level+1) end
		local frame = _G["DropDownList"..level]
		if frame and frame:IsShown() then
			local _, anchorTo = frame:GetPoint(1)
			if anchorTo and anchorTo.menuList then
				ToggleDropDownMenu(level, self:getMenuValue(level), nil, nil, nil, nil, anchorTo.menuList, anchorTo)
				return true
			end
		end
	end
	-- show my enhanced popup menu
	function lib:showMenu(menuList, frameName, anchor, x, y, autoHideDelay)
		local menuFrame = _G[frameName] or CreateFrame("Frame", frameName, UIParent, "UIDropDownMenuTemplate")
		menuFrame.displayMode = "MENU"
		menuFrame.menuValues = menuFrame.menuValues or {}
		UIDropDownMenu_Initialize(menuFrame, initialize, "MENU", nil, menuList)
		ToggleDropDownMenu(1, nil, menuFrame, anchor, x, y, menuList, nil, autoHideDelay)
	end
end
