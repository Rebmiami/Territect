--[[ json.lua
A compact pure-Lua JSON library.
The main functions are: json.stringify, json.parse.
## json.stringify:
This expects the following to be true of any tables being encoded:
 * They only have string or number keys. Number keys must be represented as
   strings in json; this is part of the json spec.
 * They are not recursive. Such a structure cannot be specified in json.
A Lua table is considered to be an array if and only if its set of keys is a
consecutive sequence of positive integers starting at 1. Arrays are encoded like
so: `[2, 3, false, "hi"]`. Any other type of Lua table is encoded as a json
object, encoded like so: `{"key1": 2, "key2": false}`.
Because the Lua nil value cannot be a key, and as a table value is considerd
equivalent to a missing key, there is no way to express the json "null" value in
a Lua table. The only way this will output "null" is if your entire input obj is
nil itself.
An empty Lua table, {}, could be considered either a json object or array -
it's an ambiguous edge case. We choose to treat this as an object as it is the
more general type.
To be clear, none of the above considerations is a limitation of this code.
Rather, it is what we get when we completely observe the json specification for
as arbitrary a Lua object as json is capable of expressing.
## json.parse:
This function parses json, with the exception that it does not pay attention to
\u-escaped unicode code points in strings.
It is difficult for Lua to return null as a value. In order to prevent the loss
of keys with a null value in a json string, this function uses the one-off
table value json.null (which is just an empty table) to indicate null values.
This way you can check if a value is null with the conditional
`val == json.null`.
If you have control over the data and are using Lua, I would recommend just
avoiding null values in your data to begin with.
--]]


json = {}


-- Internal functions.

local function kind_of(obj)
  if type(obj) ~= 'table' then return type(obj) end
  local i = 1
  for _ in pairs(obj) do
    if obj[i] ~= nil then i = i + 1 else return 'table' end
  end
  if i == 1 then return 'table' else return 'array' end
end

local function escape_str(s)
  local in_char  = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t'}
  local out_char = {'\\', '"', '/',  'b',  'f',  'n',  'r',  't'}
  for i, c in ipairs(in_char) do
    s = s:gsub(c, '\\' .. out_char[i])
  end
  return s
end

-- Returns pos, did_find; there are two cases:
-- 1. Delimiter found: pos = pos after leading space + delim; did_find = true.
-- 2. Delimiter not found: pos = pos after leading space;     did_find = false.
-- This throws an error if err_if_missing is true and the delim is not found.
local function skip_delim(str, pos, delim, err_if_missing)
  pos = pos + #str:match('^%s*', pos)
  if str:sub(pos, pos) ~= delim then
    if err_if_missing then
      error('Expected ' .. delim .. ' near position ' .. pos)
    end
    return pos, false
  end
  return pos + 1, true
end

-- Expects the given pos to be the first character after the opening quote.
-- Returns val, pos; the returned pos is after the closing quote character.
local function parse_str_val(str, pos, val)
  val = val or ''
  local early_end_error = 'End of input found while parsing string.'
  if pos > #str then error(early_end_error) end
  local c = str:sub(pos, pos)
  if c == '"'  then return val, pos + 1 end
  if c ~= '\\' then return parse_str_val(str, pos + 1, val .. c) end
  -- We must have a \ character.
  local esc_map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
  local nextc = str:sub(pos + 1, pos + 1)
  if not nextc then error(early_end_error) end
  return parse_str_val(str, pos + 2, val .. (esc_map[nextc] or nextc))
end

-- Returns val, pos; the returned pos is after the number's final character.
local function parse_num_val(str, pos)
  local num_str = str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
  local val = tonumber(num_str)
  if not val then error('Error parsing number at position ' .. pos .. '.') end
  return val, pos + #num_str
end


-- Public values and functions.

function json.stringify(obj, as_key)
  local s = {}  -- We'll build the string as an array of strings to be concatenated.
  local kind = kind_of(obj)  -- This is 'array' if it's an array or type(obj) otherwise.
  if kind == 'array' then
    if as_key then error('Can\'t encode array as key.') end
    s[#s + 1] = '['
    for i, val in ipairs(obj) do
      if i > 1 then s[#s + 1] = ', ' end
      s[#s + 1] = json.stringify(val)
    end
    s[#s + 1] = ']'
  elseif kind == 'table' then
    if as_key then error('Can\'t encode table as key.') end
    s[#s + 1] = '{'
    for k, v in pairs(obj) do
      if #s > 1 then s[#s + 1] = ', ' end
      s[#s + 1] = json.stringify(k, true)
      s[#s + 1] = ':'
      s[#s + 1] = json.stringify(v)
    end
    s[#s + 1] = '}'
  elseif kind == 'string' then
    return '"' .. escape_str(obj) .. '"'
  elseif kind == 'number' then
    if as_key then return '"' .. tostring(obj) .. '"' end
    return tostring(obj)
  elseif kind == 'boolean' then
    return tostring(obj)
  elseif kind == 'nil' then
    return 'null'
  else
    error('Unjsonifiable type: ' .. kind .. '.')
  end
  return table.concat(s)
end

json.null = {}  -- This is a one-off table to represent the null value.

function json.parse(str, pos, end_delim)
  pos = pos or 1
  if pos > #str then error('Reached unexpected end of input.') end
  local pos = pos + #str:match('^%s*', pos)  -- Skip whitespace.
  local first = str:sub(pos, pos)
  if first == '{' then  -- Parse an object.
    local obj, key, delim_found = {}, true, true
    pos = pos + 1
    while true do
      key, pos = json.parse(str, pos, '}')
      if key == nil then return obj, pos end
      if not delim_found then error('Comma missing between object items.') end
      pos = skip_delim(str, pos, ':', true)  -- true -> error if missing.
      obj[key], pos = json.parse(str, pos)
      pos, delim_found = skip_delim(str, pos, ',')
    end
  elseif first == '[' then  -- Parse an array.
    local arr, val, delim_found = {}, true, true
    pos = pos + 1
    while true do
      val, pos = json.parse(str, pos, ']')
      if val == nil then return arr, pos end
      if not delim_found then error('Comma missing between array items.') end
      arr[#arr + 1] = val
      pos, delim_found = skip_delim(str, pos, ',')
    end
  elseif first == '"' then  -- Parse a string.
    return parse_str_val(str, pos + 1)
  elseif first == '-' or first:match('%d') then  -- Parse a number.
    return parse_num_val(str, pos)
  elseif first == end_delim then  -- End of an object or array.
    return nil, pos + 1
  else  -- Parse true, false, or null.
    local literals = {['true'] = true, ['false'] = false, ['null'] = json.null}
    for lit_str, lit_val in pairs(literals) do
      local lit_end = pos + #lit_str - 1
      if str:sub(pos, lit_end) == lit_str then return lit_val, lit_end + 1 end
    end
    local pos_info_str = 'position ' .. pos .. ': ' .. str:sub(pos, pos + 10)
    error('Invalid json syntax starting at ' .. pos_info_str)
  end
end

-- return json
-- Code from https://gist.github.com/tylerneylon/59f4bcf316be525b30ab


local versionMajor = 1 -- Increment for any change that significantly changes features that older versions rely on
local versionMinor = 0 -- Increment for any change that adds new features not supported by older versions

local DataPath = "TerraGen/"
local PresetPath = DataPath .. "Presets.tgdata"
local BackupPresetPath = DataPath .. "BackupPresets.tgdata"

local MaxPresetSize = 64000 -- 64kb
local MaxPasses = 32

local function GetDefaultPass()
	return { bottom = 40, layers = { { type = elem.DEFAULT_PT_SAND, thickness = 30, variation = 5, mode = 1 }, }, settleTime = 60 }
end

local function CopyTable(table)
	local copy = {}
	for i,j in pairs(table) do
		if type(j) == "table" then
			copy[i] = CopyTable(j)
		else
			copy[i] = j
		end
	end
	return copy
end

local factoryPresets = {
	["Basic Lakes"] = '{"versionMinor":0, "versionMajor":1, "passes":[{"bottom":40, "layers":[{"type":5, "variation":5, "mode":1, "thickness":10}, {"type":47, "variation":5, "mode":1, "thickness":10}, {"type":30, "variation":5, "mode":1, "thickness":10}, {"minY":15, "mode":3, "maxY":20, "type":133, "width":120, "height":3, "veinCount":15}, {"type":5, "variation":5, "mode":1, "thickness":10}, {"minY":15, "mode":3, "maxY":35, "type":73, "width":80, "height":3, "veinCount":20}, {"type":44, "variation":5, "mode":2, "thickness":10}, {"minY":30, "mode":3, "maxY":30, "type":27, "width":60, "height":15, "veinCount":6}], "settleTime":80}, {"settleTime":160, "bottom":160, "layers":[{"type":20, "variation":3, "mode":1, "thickness":2}], "addGravityToSolids":1}]}',
	["Complex Lakes"] = '{"versionMinor":0, "versionMajor":1, "passes":[{"bottom":40, "layers":[{"type":5, "variation":5, "mode":1, "thickness":10}, {"type":47, "variation":5, "mode":1, "thickness":10}, {"type":30, "variation":5, "mode":1, "thickness":10}, {"minY":15, "mode":3, "maxY":20, "type":133, "width":120, "height":3, "veinCount":15}, {"type":5, "variation":5, "mode":1, "thickness":10}, {"minY":15, "mode":3, "maxY":35, "type":73, "width":80, "height":3, "veinCount":20}, {"type":44, "variation":5, "mode":2, "thickness":10}, {"minY":30, "mode":3, "maxY":30, "type":27, "width":60, "height":15, "veinCount":6}], "settleTime":80}, {"settleTime":160, "bottom":160, "layers":[{"type":20, "variation":3, "mode":1, "thickness":2}]}]}',
}

function removeFileExtension(filename)
	return string.gsub(filename, "(.+)%..-$", "%1")
end

function initializeFileSystem()
	-- Create missing directories
	if not fs.exists(DataPath) then
		fs.makeDirectory(DataPath)
	end
	if not fs.exists(PresetPath) then
		local f = io.open(PresetPath, "w")
		f:write("{}")
		f:close()
	end
end

initializeFileSystem()

loadedPresets = {}

function saveChanges()
	local tableToSave = {}
	for folderName,folderData in pairs(loadedPresets) do
		if folderName ~= "Factory" then
			tableToSave[folderName] = folderData 
		end
	end
	local f = io.open(PresetPath, "w")
	f:write(json.stringify(tableToSave))
	f:close()
end

local fPreset = {
	passes = {
		{
			bottom = 40,
			layers = {
				{ type = elem.DEFAULT_PT_STNE, thickness = 10, variation = 5, mode = 1 },
				{ type = elem.DEFAULT_PT_BGLA, thickness = 10, variation = 5, mode = 1 },
				{ type = elem.DEFAULT_PT_BRMT, thickness = 10, variation = 5, mode = 1 },
				{ type = elem.DEFAULT_PT_PQRT, veinCount = 15, minY = 15, maxY = 20, width = 120, height = 3, mode = 3 },
				{ type = elem.DEFAULT_PT_STNE, thickness = 10, variation = 5, mode = 1 },
				{ type = elem.DEFAULT_PT_BCOL, veinCount = 20, minY = 15, maxY = 35, width = 80, height = 3, mode = 3 },
				{ type = elem.DEFAULT_PT_SAND, thickness = 10, variation = 5, mode = 2 },
				{ type = elem.DEFAULT_PT_SLTW, veinCount = 6, minY = 30, maxY = 30, width = 60, height = 15, mode = 3 },
			},
			settleTime = 80
		},
		{
			bottom = 160,
			layers = {
				{ type = elem.DEFAULT_PT_PLNT, thickness = 2, variation = 3, mode = 1 },
			},
			addGravityToSolids = 1,
			settleTime = 160
		}
	},
	versionMajor = 1,
	versionMinor = 0
}

local terraGenParams

-- Reload presets
function reloadPresets()
	local f = io.open(PresetPath, "r")
	loadedPresets = json.parse(f:read("*all"))
	loadedPresets["Factory"] = {}
	for k,j in pairs(factoryPresets) do
		if not loadedPresets["Factory"] then  end
		loadedPresets["Factory"][k] = j
	end
end

reloadPresets()


local genDropDownX = 4
local genDropDownY = -10
local genDropWidth = 60
local genDropHeight = 14
local genDropDownYOff = 0
local genDropDownHovered = 0
local genDropDownClicked = 0

local terraGenCoroutine
local terraGenRunning = false

event.register(event.tick, function()
    local x = tpt.mousex
    local y = tpt.mousey
    local modifiedY = genDropDownYOff + genDropDownY
	if (x >= genDropDownX and x <= genDropDownX + genDropWidth) and (y >= modifiedY and y <= modifiedY + genDropHeight) then
        genDropDownYOff = math.min(genDropDownYOff + 1, 10)
    else
        genDropDownYOff = math.max(genDropDownYOff - 1, 0)
    end

	if elem.T_PT_PDRD then -- Make room for Powderizer buttons
		genDropDownX = 50
	end

    graphics.fillRect(genDropDownX, modifiedY, genDropWidth, genDropHeight, 0, 0, 0)
    graphics.drawRect(genDropDownX, modifiedY, genDropWidth, genDropHeight, 255, 255, 255)
    graphics.drawText(genDropDownX + 3, modifiedY + 3, "TerraGen", 255, 255, 255)
end)


local selectedFolder = nil
local selectedPreset = nil
-- Main window
local terraGenWindowWidth = 300
local terraGenWindowHeight = 260
local terraGenWindow = Window:new(-1, -1, terraGenWindowWidth, terraGenWindowHeight)

-- Code for preset editor further below
local presetEditorWindowWidth = 470
local presetEditorWindowHeight = 260
local presetEditorWindow = Window:new(-1, -1, presetEditorWindowWidth, presetEditorWindowHeight)
local workingPreset = nil

local versionText = "Terragen v" .. versionMajor .. "." .. versionMinor
local versionLabelSize = graphics.textSize(warningLabel)
local versionLabel = Label:new(terraGenWindowWidth / 2 - versionLabelSize / 2, 5, versionLabelSize, 16, versionText)

-- Folder selector box
local selectorBoxPadding = 10
local selectorBoxWidth = terraGenWindowWidth / 2 - selectorBoxPadding * 2
local selectorBoxHeight = 100
local selectorBoxY = selectorBoxPadding + 15
local folderSelectorBoxX = selectorBoxPadding
local folderSelectorBox = Button:new(folderSelectorBoxX, selectorBoxY, selectorBoxWidth, selectorBoxHeight)
folderSelectorBox:enabled(false)

function tryAddCopyNumber(table, name)
	local foundName = false
	local num = 1
	local newName
	repeat
		newName = name .. " (" .. num .. ")"
		foundName = not table[newName]
		num = num + 1
	until foundName or num > 99
	if num > 99 then
		return nil, num
	end
	return newName, num
end

local windowsReservedNames = {"CON", "PRN", "AUX", "NUL",
	"COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
	"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
}
function isNameValid(table, name, itemtype)
	-- Note: Do not make checks only apply to the platforms they affect; presets will be shared across different machines.
	if name == "" then
		return false, "Please enter 1 or more characters."
	end
	if table[name] then
		return false, "There already exists a " .. itemtype .. " named '" .. name .. "'."
	end
	if #name > 48 then
		return false, "Too long. Please use fewer than 48 characters."
	end
	return true
end

-- New folder button
local selectorBottom = selectorBoxY + selectorBoxHeight + 5
local newFolderButton = Button:new(folderSelectorBoxX, selectorBottom, selectorBoxWidth, 16, "New")
newFolderButton:action(
    function()
		local name = tpt.input("New Folder", "Name the folder:", "New Folder") 
		if #name == 0 then return end
		local validName, message = isNameValid(loadedPresets, name, "folder")
		if validName then
			selectedFolder = name
			selectedPreset = nil
			loadedPresets[name] = {}
			refreshWindowFolders()
			refreshWindowPresets()
			updateButtons()

			saveChanges()
		else
			tpt.message_box("Invalid Name", message)
		end
    end
)
-- Delete folder button
local deleteFolderButton = Button:new(folderSelectorBoxX, selectorBottom + 18, selectorBoxWidth, 16, "Delete")
deleteFolderButton:action(
    function()
		local presets = 0
		for n,o in pairs(loadedPresets[selectedFolder]) do
			presets = presets + 1
		end
		local toDelete = true
		if presets > 0 then
			toDelete = tpt.confirm("Delete Folder", "Delete the folder '" .. selectedFolder .. "' and the " .. presets .. " presets inside?", "Delete")
		end
		if toDelete then
			loadedPresets[selectedFolder] = nil
			selectedFolder = nil
			selectedPreset = nil
			refreshWindowFolders()
			refreshWindowPresets()
			updateButtons()

			saveChanges()
		end
	end
)

local presetSelectorBoxX = terraGenWindowWidth - selectorBoxPadding - selectorBoxWidth
local presetSelectorBox = Button:new(presetSelectorBoxX, selectorBoxY, selectorBoxWidth, selectorBoxHeight)
presetSelectorBox:enabled(false)

-- New preset button
local newPresetButton = Button:new(presetSelectorBoxX, selectorBottom, selectorBoxWidth / 2 - 1, 16, "New")
newPresetButton:action(
function()
	local name = tpt.input("New Preset", "Name the preset:", "New Preset") 
	if #name == 0 then return end
	local validName, message = isNameValid(loadedPresets[selectedFolder], name, "preset")
	if validName then
		loadedPresets[selectedFolder][name] = json.stringify({
			passes = {
				GetDefaultPass()
			},
			versionMajor = versionMajor,
			versionMinor = versionMinor
		})
		selectedPreset = name
		refreshWindowFolders()
		refreshWindowPresets()
		updateButtons()

		saveChanges()
	else
		tpt.message_box("Invalid Name", message)
	end
end)

local editPresetButton = Button:new(presetSelectorBoxX + selectorBoxWidth / 2 + 1, selectorBottom, selectorBoxWidth / 2 - 1, 16, "Edit")
editPresetButton:action(
function()
	setupEditorWindow()
	interface.showWindow(presetEditorWindow)

	saveChanges()
	-- tpt.message_box("Pretend things are getting edited", "Please travel into the future where Reb has implemented the edit screen.")
end)

local deletePresetButton = Button:new(presetSelectorBoxX, selectorBottom + 18, selectorBoxWidth / 2 - 1, 16, "Delete")
deletePresetButton:action(
function()
	local toDelete = tpt.confirm("Delete Preset", "Delete the preset '" .. selectedPreset .. "'?", "Delete")
	if toDelete then
		loadedPresets[selectedFolder][selectedPreset] = nil
		selectedPreset = nil
		refreshWindowFolders()
		refreshWindowPresets()
		updateButtons()

		saveChanges()
	end
end)

local clonePresetButton = Button:new(presetSelectorBoxX + selectorBoxWidth / 2 + 1, selectorBottom + 18, selectorBoxWidth / 2 - 1, 16, "Clone")
clonePresetButton:action(
function()
	local newName, num = tryAddCopyNumber(loadedPresets[selectedFolder], selectedPreset)
	if newName == nil then
		tpt.message_box("Cloning Failed", "Cloning failed. Reason: Too many copies with the same name.")
		return
	end
	-- if newName == nil then newName = "New Preset" end
	loadedPresets[selectedFolder][newName] = loadedPresets[selectedFolder][selectedPreset]
	refreshWindowFolders()
	refreshWindowPresets()

	saveChanges()
end)

local extraButtonOffset = selectorBottom + 46
local extraButtonAddWidth = 9
local extraButtonWidth = selectorBoxWidth + extraButtonAddWidth
local userSettingButton = Button:new(folderSelectorBoxX, extraButtonOffset, extraButtonWidth, 16, "Settings")
userSettingButton:action(
function()
	tpt.message_box("Pretend things are getting configured", "Please travel into the future where Reb has implemented the settings screen.")
end)

local presetSaveButton = Button:new(presetSelectorBoxX - extraButtonAddWidth, extraButtonOffset, extraButtonWidth, 16, "Create Preset Save")
presetSaveButton:action(
function()
	tpt.message_box("Pretend preset saves are getting created", "Please travel into the future where Reb has implemented the preset save screen.")
end)

local bugReportButton = Button:new(folderSelectorBoxX, extraButtonOffset + 18, extraButtonWidth, 16, "Report Bug")
bugReportButton:action(
function()
	platform.openLink("https://github.com/Rebmiami/TerraGen/issues/new?assignees=&labels=bug&template=bug_report.md&title=%5BBUG%5D")
end)

local suggestFeatureButton = Button:new(presetSelectorBoxX - extraButtonAddWidth, extraButtonOffset + 18, extraButtonWidth, 16, "Suggest Feature")
suggestFeatureButton:action(
function()
	platform.openLink("https://github.com/Rebmiami/TerraGen/issues/new?assignees=&labels=enhancement&template=feature_request.md&title=%5BSUGGESTION%5D")
end)







-- Warning label
local warningLabel = "Warning: The current simulation will be cleared!"
local warningLabelSize = graphics.textSize(warningLabel)
local testLabel = Label:new((select(1, terraGenWindow:size())/2) - warningLabelSize / 2, terraGenWindowHeight - 46, warningLabelSize, 16, warningLabel)

-- Go button
local goButton = Button:new(10, terraGenWindowHeight-26, 100, 16, "Go!")

function updateButtons()
	if selectedFolder == "Factory" then
		goButton:enabled(loadedPresets[selectedFolder] ~= nil and loadedPresets[selectedFolder][selectedPreset] ~= nil)
		deleteFolderButton:enabled(false)
		editPresetButton:enabled(true) -- CHANGE
		deletePresetButton:enabled(false)
		clonePresetButton:enabled(false)
		newPresetButton:enabled(false)
	else
		goButton:enabled(loadedPresets[selectedFolder] ~= nil and loadedPresets[selectedFolder][selectedPreset] ~= nil)
		deleteFolderButton:enabled(loadedPresets[selectedFolder] ~= nil)
		editPresetButton:enabled(loadedPresets[selectedFolder] ~= nil and loadedPresets[selectedFolder][selectedPreset] ~= nil)
		deletePresetButton:enabled(loadedPresets[selectedFolder] ~= nil and loadedPresets[selectedFolder][selectedPreset] ~= nil)
		clonePresetButton:enabled(loadedPresets[selectedFolder] ~= nil and loadedPresets[selectedFolder][selectedPreset] ~= nil)
		newPresetButton:enabled(loadedPresets[selectedFolder] ~= nil)
	end
end

updateButtons()

goButton:action(
    function()
		terraGenParams = json.parse(loadedPresets[selectedFolder][selectedPreset])

		if terraGenParams.versionMajor > versionMajor then
			tpt.message_box("Please Update TerraGen", "You are using TerraGen v" .. versionMajor .. "." .. versionMinor .. ", but this preset requires TerraGen v" .. terraGenParams.versionMajor .. "." .. terraGenParams.versionMinor .. ". Please update TerraGen from the Lua browser.")
			return
		elseif terraGenParams.versionMajor == versionMajor and terraGenParams.versionMinor > versionMinor then
			local ignoreProblems = tpt.confirm("Please Update TerraGen", "You are using TerraGen v" .. versionMajor .. "." .. versionMinor .. ", but this preset requires TerraGen v" .. terraGenParams.versionMajor .. "." .. terraGenParams.versionMinor .. ". Please update TerraGen from the Lua browser.\n\nDo you wish to continue anyways? Errors or undesired behavior may occur.", "Run Anyway")
			if not ignoreProblems then
				return
			end
		end
		
        interface.closeWindow(terraGenWindow)
        sim.clearSim()
        tpt.set_pause(0)
		terraGenCoroutine = coroutine.create(runTerraGen)
		coroutine.resume(terraGenCoroutine)
		terraGenRunning = true
    end
)


local closeButton = Button:new(select(1, terraGenWindow:size())-110, select(2, terraGenWindow:size())-26, 100, 16, "Cancel")

closeButton:action(
    function()
        interface.closeWindow(terraGenWindow)
    end
)

terraGenWindow:addComponent(versionLabel)

terraGenWindow:addComponent(folderSelectorBox)
terraGenWindow:addComponent(newFolderButton)
terraGenWindow:addComponent(deleteFolderButton)

terraGenWindow:addComponent(presetSelectorBox)
terraGenWindow:addComponent(newPresetButton)
terraGenWindow:addComponent(editPresetButton)
terraGenWindow:addComponent(deletePresetButton)
terraGenWindow:addComponent(clonePresetButton)

terraGenWindow:addComponent(userSettingButton)
terraGenWindow:addComponent(presetSaveButton)
terraGenWindow:addComponent(bugReportButton)
terraGenWindow:addComponent(suggestFeatureButton)

terraGenWindow:addComponent(testLabel)
terraGenWindow:addComponent(goButton)
terraGenWindow:addComponent(closeButton)



local selectorButtonHeight = 16

local windowFolderSelections = {}
function refreshWindowFolders()
	for k,j in pairs(windowFolderSelections) do
		terraGenWindow:removeComponent(k)
	end
	windowFolderSelections = {}
	local i = 0
	for k,j in pairs(loadedPresets) do
		local folderButton = Button:new(folderSelectorBoxX, selectorBoxY + (selectorButtonHeight - 1) * i, selectorBoxWidth, selectorButtonHeight)
		folderButton:action(
			function()
				selectedPreset = nil
				selectedFolder = windowFolderSelections[folderButton]
				refreshWindowPresets()
				refreshFolderSelectionText()
				updateButtons()
			end
		)
		windowFolderSelections[folderButton] = k
		terraGenWindow:addComponent(folderButton)
		i = i + 1
	end
	refreshFolderSelectionText()
	-- refreshPresetSelectionText()
end

function refreshFolderSelectionText()
	for l,m in pairs(windowFolderSelections) do
		local presets = 0
		for n,o in pairs(loadedPresets[m]) do
			presets = presets + 1
		end
		if m == selectedFolder then
			l:text("> " .. m .. " [" .. presets .. "] <")
		else
			l:text(m .. " [" .. presets .. "]")
		end
	end
end


local windowPresetSelections = {}

function refreshWindowPresets()
	for k,j in pairs(windowPresetSelections) do
		terraGenWindow:removeComponent(k)
	end
	windowPresetSelections = {}
	if loadedPresets[selectedFolder] then
		local i = 0
		for k,j in pairs(loadedPresets[selectedFolder]) do
			local presetButton = Button:new(presetSelectorBoxX, selectorBoxY + (selectorButtonHeight - 1) * i, selectorBoxWidth, selectorButtonHeight)
			presetButton:action(
				function()
					selectedPreset = windowPresetSelections[presetButton]
					refreshPresetSelectionText()
					updateButtons()
				end
			)
			windowPresetSelections[presetButton] = removeFileExtension(k)
			terraGenWindow:addComponent(presetButton)
			i = i + 1
		end
	end
	-- refreshFolderSelectionText()
	refreshPresetSelectionText()
end

function refreshPresetSelectionText()
	for l,m in pairs(windowPresetSelections) do
		if m == selectedPreset then
			l:text("> " .. m .. " <")
		else
			l:text(m)
		end
	end
end

-- Preset Editor

local selectedPass = nil
local selectedLayer = nil

local saveButton = Button:new(presetEditorWindowWidth-220, presetEditorWindowHeight-26, 100, 16, "Save & Close")
saveButton:action(
    function()
		loadedPresets[selectedFolder][selectedPreset] = json.stringify(workingPreset)
		workingPreset = nil
        interface.closeWindow(presetEditorWindow)
    end
)

local passText = "Passes:"
local passLabelSize = graphics.textSize(passText)
local passLabel = Label:new(presetEditorWindowWidth / 2 - passLabelSize / 2, 5, passLabelSize, 16, passText)
presetEditorWindow:addComponent(passLabel)

local presetSelectorBoxPadding = 10
local passSelectorBoxWidth = presetEditorWindowWidth - presetSelectorBoxPadding * 2
local passSelectorBoxX = presetEditorWindowWidth - presetSelectorBoxPadding - passSelectorBoxWidth
local passSelectorBoxHeight = 15
local passSelectorBox = Button:new(passSelectorBoxX, selectorBoxY, passSelectorBoxWidth - 1, passSelectorBoxHeight)
passSelectorBox:enabled(false)
presetEditorWindow:addComponent(passSelectorBox)

local addPassButton = Button:new(passSelectorBoxX, selectorBoxY + 18, passSelectorBoxHeight, passSelectorBoxHeight, "+")
addPassButton:action(
    function()
		if selectedPass then
			table.insert(workingPreset.passes, selectedPass + 1, GetDefaultPass())
			selectedPass = selectedPass + 1
		else
			table.insert(workingPreset.passes, GetDefaultPass())
			selectedPass = #workingPreset.passes
		end
		
		selectedLayer = nil
		refreshWindowPasses()
		updatePresetButtons()
    end
)
presetEditorWindow:addComponent(addPassButton)

local deletePassButton = Button:new(passSelectorBoxX + 18 * 1, selectorBoxY + 18, passSelectorBoxHeight, passSelectorBoxHeight, "-")
deletePassButton:action(
    function()
		table.remove(workingPreset.passes, selectedPass)
		if selectedPass > #workingPreset.passes then
			selectedPass = #workingPreset.passes
		end
		if not workingPreset.passes[selectedPass] then
			selectedPass = nil
		end
		
		selectedLayer = nil
		refreshWindowPasses()
		updatePresetButtons()
    end
)
presetEditorWindow:addComponent(deletePassButton)

local movePassLeftButton = Button:new(passSelectorBoxX + 18 * 2, selectorBoxY + 18, passSelectorBoxHeight, passSelectorBoxHeight, "<")
movePassLeftButton:action(
    function()
		workingPreset.passes[selectedPass], workingPreset.passes[selectedPass - 1] = workingPreset.passes[selectedPass - 1], workingPreset.passes[selectedPass]
		selectedPass = selectedPass - 1
		refreshWindowPasses()
		updatePresetButtons()
    end
)
presetEditorWindow:addComponent(movePassLeftButton)

local movePassRightButton = Button:new(passSelectorBoxX + 18 * 3, selectorBoxY + 18, passSelectorBoxHeight, passSelectorBoxHeight, ">")
movePassRightButton:action(
    function()
		workingPreset.passes[selectedPass], workingPreset.passes[selectedPass + 1] = workingPreset.passes[selectedPass + 1], workingPreset.passes[selectedPass]
		selectedPass = selectedPass + 1
		refreshWindowPasses()
		updatePresetButtons()
    end
)
presetEditorWindow:addComponent(movePassRightButton)

local clonePassButton = Button:new(passSelectorBoxX + 18 * 4, selectorBoxY + 18, passSelectorBoxHeight, passSelectorBoxHeight, "C")
clonePassButton:action(
    function()
		table.insert(workingPreset.passes, selectedPass + 1, CopyTable(workingPreset.passes[selectedPass]))
		selectedPass = selectedPass + 1
		
		refreshWindowPasses()
		updatePresetButtons()
    end
)
presetEditorWindow:addComponent(clonePassButton)

local windowPassSelections = {}
function refreshWindowPasses()
	for k,j in pairs(windowPassSelections) do
		presetEditorWindow:removeComponent(k)
	end
	windowPassSelections = {}
	for k,j in pairs(workingPreset.passes) do
		local passButton = Button:new(passSelectorBoxX + (passSelectorBoxHeight - 1) * (k - 1), selectorBoxY, passSelectorBoxHeight, passSelectorBoxHeight)
		passButton:text(k .. "")
		passButton:action(
			function()
				selectedLayer = nil
				selectedPass = windowPassSelections[passButton]
				-- refreshWindowPresets()
				refreshPassSelectionFade()
				updatePresetButtons()
			end
		)
		windowPassSelections[passButton] = k
		presetEditorWindow:addComponent(passButton)
	end
	refreshPassSelectionFade()
	-- refreshPresetSelectionText()
end

function refreshPassSelectionFade()
	for l,m in pairs(windowPassSelections) do
		l:enabled(m ~= selectedPass) 
	end
end

local passButtonHeight = selectorBoxY + 18

local settleHeightText = "Settle Height (px):"
local settleHeightLabelSize = graphics.textSize(settleHeightText)
local settleHeightLabel = Label:new(passSelectorBoxX + 95, passButtonHeight, settleHeightLabelSize, 16, settleHeightText)
presetEditorWindow:addComponent(settleHeightLabel)

local settleHeightTextbox = Textbox:new(passSelectorBoxX + settleHeightLabelSize + 100, passButtonHeight, 40, 16)
settleHeightTextbox:onTextChanged(
	function(sender)
		local newValue = tonumber(sender:text())
		if sender:text() == "" then newValue = 0 end
		if newValue then
			workingPreset.passes[selectedPass].bottom = math.max(math.floor(newValue), 0) -- Positive integers only
		else
			-- tpt.message_box("Invalid Number", sender:text() .. " is not a valid number.")
			sender:text(workingPreset.passes[selectedPass].bottom)
		end
	end)
presetEditorWindow:addComponent(settleHeightTextbox)

local settleTimeText = "Settle Time (f):"
local settleTimeLabelSize = graphics.textSize(settleTimeText)
local settleTimeLabel = Label:new(passSelectorBoxX + 235, passButtonHeight, settleTimeLabelSize, 16, settleTimeText)
presetEditorWindow:addComponent(settleTimeLabel)

local settleTimeTextbox = Textbox:new(passSelectorBoxX + settleTimeLabelSize + 240, passButtonHeight, 40, 16)
settleTimeTextbox:onTextChanged(
	function(sender)
		local newValue = tonumber(sender:text())
		if sender:text() == "" then newValue = 0 end
		if newValue then
			workingPreset.passes[selectedPass].settleTime = math.max(math.floor(newValue), 0) -- Positive integers only
		else
			-- tpt.message_box("Invalid Number", sender:text() .. " is not a valid number.")
			sender:text(workingPreset.passes[selectedPass].settleTime)
		end
	end)
presetEditorWindow:addComponent(settleTimeTextbox)

local solidGravityCheckbox = Checkbox:new(passSelectorBoxX + 360, passButtonHeight, 50, 16, "Solid Gravity");
solidGravityCheckbox:action(
	function(sender, checked)
		if selectedPass ~= nil then
			if checked then
				workingPreset.passes[selectedPass].addGravityToSolids = true
			else
				workingPreset.passes[selectedPass].addGravityToSolids = nil
			end
		end
	end)
presetEditorWindow:addComponent(solidGravityCheckbox)

local saveButton = Button:new(presetEditorWindowWidth-220, presetEditorWindowHeight-26, 100, 16, "Save & Close")
saveButton:action(
    function()
		loadedPresets[selectedFolder][selectedPreset] = json.stringify(workingPreset)
		workingPreset = nil
        interface.closeWindow(presetEditorWindow)
    end
)
presetEditorWindow:addComponent(saveButton)

local presetCloseButton = Button:new(presetEditorWindowWidth-110, presetEditorWindowHeight-26, 100, 16, "Discard Changes")
presetCloseButton:action(
    function()
		workingPreset = nil
        interface.closeWindow(presetEditorWindow)
    end
)
presetEditorWindow:addComponent(presetCloseButton)

function updatePresetButtons()
	addPassButton:enabled(#workingPreset.passes < MaxPasses)
	deletePassButton:enabled(selectedPass ~= nil)
	movePassLeftButton:enabled(selectedPass ~= nil and selectedPass > 1)
	movePassRightButton:enabled(selectedPass ~= nil and selectedPass < #workingPreset.passes)
	clonePassButton:enabled(selectedPass ~= nil and #workingPreset.passes < MaxPasses)

	settleHeightTextbox:readonly(selectedPass == nil)
	if selectedPass ~= nil then 
		settleHeightTextbox:text(tostring(workingPreset.passes[selectedPass].bottom)) 
	else 
		settleHeightTextbox:text("") 
	end

	settleTimeTextbox:readonly(selectedPass == nil)
	if selectedPass ~= nil then 
		settleTimeTextbox:text(tostring(workingPreset.passes[selectedPass].settleTime)) 
	else 
		settleTimeTextbox:text("") 
	end

	if selectedPass ~= nil then 
		solidGravityCheckbox:checked(workingPreset.passes[selectedPass].addGravityToSolids)
	else
		solidGravityCheckbox:checked(false)
	end
end




function setupEditorWindow()
	workingPreset = json.parse(loadedPresets[selectedFolder][selectedPreset])
	selectedPass = nil
	selectedLayer = nil

	refreshWindowPasses()
	updatePresetButtons()
end



local flashTimer = 0
local terraGenStaticMessage = "TerraGen is running..."
local terraGenStatus = "Idle"

event.register(event.tick, function()
    if terraGenRunning then
		local brightness = 180 - math.sin(flashTimer * math.pi / 15) * 20
		local w, h = graphics.textSize(terraGenStaticMessage)
		graphics.drawText(sim.XRES / 2 - w / 2, 25, terraGenStaticMessage, brightness, brightness, brightness)
		local w, h = graphics.textSize(terraGenStatus)
		graphics.drawText(sim.XRES / 2 - w / 2, 40, terraGenStatus, brightness, brightness, brightness)
		flashTimer = (flashTimer + 1) % 30
		coroutine.resume(terraGenCoroutine)
	end
end)











------ TERRAIN GENERATION ------


-- Mode list explanation:
-- 1: Uniform layer
-- 2: Uniform layer w/ padding
-- 3: Veins
local terraGenFunctions = {
	[1] = function(j, xH, vtk) 
		for i=0,sim.XRES do
			local amt = j.thickness + (math.random() - 0.5) * j.variation
			for l=0,amt do
				vtk[i][xH[i]] = j.type 
				xH[i] = xH[i] + 1
			end
		end
		return j, xH, vtk
	end,
	[2] = function(j, xH, vtk) 
		local max = 0
		for i=0,sim.XRES do
			max = math.max(max, xH[i])
		end
		for i=0,sim.XRES do
			xH[i] = max
			local amt = j.thickness + (math.random() - 0.5) * j.variation
			for l=0,amt do
				vtk[i][xH[i]] = j.type 
				xH[i] = xH[i] + 1
			end
		end
		return j, xH, vtk
	end,
	[3] = function(j, xH, vtk)
		for v=1,j.veinCount do
			local x = math.random(sim.XRES)
			local y = math.random(j.minY, j.maxY)
			for k=0,j.width do
				for l=0,j.height do
					local dx = math.floor(x + k - j.width / 2)
					local dy = math.floor(y + l - j.height / 2)
					if vtk[dx] ~= nil and (math.abs(dx - x) / j.width) + (math.abs(dy - y) / j.height) < 0.5 then
						vtk[dx][dy] = j.type
					end
				end
			end
		end

		return j, xH, vtk
	end
}




function runTerraGen()
	terraGenStatus = "Running"

	for n,p in pairs(terraGenParams.passes) do
		terraGenStatus = "Generating Pass " .. n
		local vtk = {}
		local xH = {}
		for i=0,sim.XRES do
			xH[i] = 0
			vtk[i] = {}
		end
	
		local originalProperties = {}
		for k,j in pairs(p.layers) do
			terraGenStatus = "Generating Pass " .. n .. ": Layer " .. k .. "/" .. #p.layers
			j, xH, vtk = terraGenFunctions[j.mode](j, xH, vtk)

			if p.addGravityToSolids and bit.band(elem.property(j.type, "Properties"), elem.TYPE_SOLID) ~= 0 and not originalProperties[j.type] then
				if p.solidPhysicsSource then
					-- TODO: Clone physics of specified source element
				else
					originalProperties[j.type] = {
						Falldown = elem.property(j.type, "Falldown"),
						Loss = elem.property(j.type, "Loss"),
						Gravity = elem.property(j.type, "Gravity"),
						Properties = elem.property(j.type, "Properties"),
						Weight = elem.property(j.type, "Weight"),
					}
					elem.property(j.type, "Falldown", 1)
					elem.property(j.type, "Loss", 0.99)
					elem.property(j.type, "Gravity", 0.02)
					elem.property(j.type, "Properties", elem.TYPE_PART)
					elem.property(j.type, "Weight", 90)
				end
			end
		end
			
	
		terraGenStatus = "Drawing Pass " .. n
		for i=0,sim.XRES do
			for k,j in pairs(vtk[i]) do
				sim.partCreate(-1, i, sim.YRES - p.bottom - k, j)
			end
			if i % 10 == 0 then
				coroutine.yield()
			end
		end

		terraGenStatus = "Settling"
		for i=0,p.settleTime do
			coroutine.yield()
		end

		for k,j in pairs(originalProperties) do
			for l,m in pairs(j) do
				elem.property(k, l, m)
			end
		end
	end
	

	terraGenRunning = false
end





function terraGen()
	refreshWindowFolders()
    interface.showWindow(terraGenWindow)
end

event.register(event.mousedown, function(x, y, button)
    local modifiedY = genDropDownYOff + genDropDownY
	if (x >= genDropDownX and x <= genDropDownX + genDropWidth) and (y >= modifiedY and y <= modifiedY + genDropHeight) then
        terraGen()
		return false
    else

    end
end) 

-- Create a backup copy of the preset folder when the game is closed
event.register(event.close, function()
    fs.copy(PresetPath, BackupPresetPath)
end) 