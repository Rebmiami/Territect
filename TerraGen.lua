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
local PresetPath = DataPath .. "Presets/"
local FactoryPresetPath = PresetPath .. "Factory/"


local factoryPresets = {
	["Basic Lakes"] = '{"versionMinor":0, "versionMajor":1, "passes":[{"bottom":40, "layers":[{"type":5, "variation":5, "mode":1, "thickness":10}, {"type":47, "variation":5, "mode":1, "thickness":10}, {"type":30, "variation":5, "mode":1, "thickness":10}, {"minY":15, "mode":3, "maxY":20, "type":133, "width":120, "height":3, "veinCount":15}, {"type":5, "variation":5, "mode":1, "thickness":10}, {"minY":15, "mode":3, "maxY":35, "type":73, "width":80, "height":3, "veinCount":20}, {"type":44, "variation":5, "mode":2, "thickness":10}, {"minY":30, "mode":3, "maxY":30, "type":27, "width":60, "height":15, "veinCount":6}], "settleTime":80}, {"settleTime":160, "bottom":160, "layers":[{"type":20, "variation":3, "mode":1, "thickness":2}], "addGravityToSolids":1}]}'
}

function removeFileExtension(filename)
	return string.gsub(filename, "(.+)%..-$", "%1")
end

function initializeFS()
	-- Create missing directories
	if not fs.exists(DataPath) then
		fs.makeDirectory(DataPath)
	end
	if not fs.exists(PresetPath) then
		fs.makeDirectory(PresetPath)
	end
	if not fs.exists(FactoryPresetPath) then
		fs.makeDirectory(FactoryPresetPath)
	end

	-- Add missing files
	local files = fs.list(FactoryPresetPath)
	for k,j in pairs(factoryPresets) do
		if not fs.exists(FactoryPresetPath .. k .. ".tgpreset") then
			local f = io.open(FactoryPresetPath .. k .. ".tgpreset", "w")
			f:write(j)
		end
	end
end

initializeFS()

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
	versionMinor = 1
}
local terraGenParams

loadedPresets = {

}

-- Reload presets
function reloadPresets(folder)
	print(folder)
	if folder then
		if folder == "Factory" then
			for k,j in pairs(factoryPresets) do
				if not loadedPresets["Factory"] then loadedPresets["Factory"] = {} end
				loadedPresets["Factory"][k] = j
			end
		else
			local files = fs.list(PresetPath .. folder)
			for k,j in pairs(files) do
				if fs.isFile(PresetPath .. folder .. "/" .. j) then
					local f = io.open(PresetPath .. folder .. "/" .. j, "r")
					if not loadedPresets[folder] then loadedPresets[folder] = {} end
					loadedPresets[folder][removeFileExtension(j)] = f:read("*all")
				end
			end
		end
		return
	end
	local folders = fs.list(PresetPath)
	for k,j in pairs(folders) do
		if fs.isDirectory(PresetPath .. j) then
			reloadPresets(j)
		end
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

    graphics.fillRect(genDropDownX, modifiedY, genDropWidth, genDropHeight, 0, 0, 0)
    graphics.drawRect(genDropDownX, modifiedY, genDropWidth, genDropHeight, 255, 255, 255)
    graphics.drawText(genDropDownX + 3, modifiedY + 3, "TerraGen", 255, 255, 255)
end)


-- Main window
local terraGenWindowWidth = 300
local terraGenWindowHeight = 200
local terraGenWindow = Window:new(-1, -1, terraGenWindowWidth, terraGenWindowHeight)

-- Folder selector box
local selectorBoxPadding = 10
local selectorBoxWidth = terraGenWindowWidth / 2 - selectorBoxPadding * 2
local selectorBoxHeight = 100
local folderSelectorBoxX = selectorBoxPadding
local folderSelectorBoxY = selectorBoxPadding
local folderSelectorBox = Button:new(folderSelectorBoxX, folderSelectorBoxY, selectorBoxWidth, selectorBoxHeight)
folderSelectorBox:enabled(false)

local presetSelectorBoxX = terraGenWindowWidth - selectorBoxPadding - selectorBoxWidth
local presetSelectorBoxY = selectorBoxPadding
local presetSelectorBox = Button:new(presetSelectorBoxX, presetSelectorBoxY, selectorBoxWidth, selectorBoxHeight)
presetSelectorBox:enabled(false)

-- Warning label
local warningLabel = "Warning: The current simulation will be cleared!"
local warningLabelSize = graphics.textSize(warningLabel)
local testLabel = Label:new((select(1, terraGenWindow:size())/2) - warningLabelSize / 2, terraGenWindowHeight - 46, warningLabelSize, 16, warningLabel)

-- Go button
local goButton = Button:new(10, terraGenWindowHeight-26, 100, 16, "Go!")

local selectedFolder = "Factory"
local selectedPreset = "Basic Lakes"

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

terraGenWindow:addComponent(folderSelectorBox)
terraGenWindow:addComponent(presetSelectorBox)
terraGenWindow:addComponent(testLabel)
terraGenWindow:addComponent(goButton)
terraGenWindow:addComponent(closeButton)



local selectorButtonHeight = 16

function refreshWindowFolders()
	local i = 0 -- Could use ipairs but both numeric and string index are required
	for k,j in pairs(loadedPresets) do
		local folderButton = Button:new(folderSelectorBoxX, folderSelectorBoxY + selectorButtonHeight * i, selectorBoxWidth, selectorButtonHeight)
		folderButton:text(k)
		folderButton:action(
			function()
				selectedFolder = k
				refreshWindowPresets()
			end
		)
		terraGenWindow:addComponent(folderButton)
		i = i + 1
	end
end

function refreshWindowPresets()
	local i = 0 -- Could use ipairs but both numeric and string index are required
	for k,j in pairs(loadedPresets[selectedFolder]) do
		local presetButton = Button:new(presetSelectorBoxX, presetSelectorBoxY + selectorButtonHeight * (i), selectorBoxWidth, selectorButtonHeight)
		presetButton:text(removeFileExtension(k))
		presetButton:action(
			function()
				selectedPreset = removeFileExtension(k)
			end
		)
		terraGenWindow:addComponent(presetButton)
		i = i + 1
	end
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

-- Mode list explanation:
-- 1: Uniform layer
-- 2: Uniform layer w/ padding
-- 3: Veins




-- local f = io.open(PresetPath .. "TryMe.tgpreset", "w")
-- print (json.stringify(terraGenParams))
-- f:write(json.stringify(terraGenParams))






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

			if p.addGravityToSolids and bit.band(elem.property(j.type, "Properties"), elem.TYPE_SOLID) then
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