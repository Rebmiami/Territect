
-- Set to true to enable certain developer features
-- Should always be false on releases
local devMode = true

-- How many times to create a backup when the game is closed
local backups = 2

-- Check if the current snapshot supports tmp3/tmp4
-- Otherwise, use pavg0/1
local tmp3 = "pavg0"
local tmp4 = "pavg1"
if sim.FIELD_TMP3 then -- Returns nil if tmp3 is not part of the current snapshot
	tmp3 = "tmp3"
	tmp4 = "tmp4"
end


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

local OldDataPath = "TerraGen/"
local DataPath = "Territect/"
local PresetPath = DataPath .. "Presets.tgdata"
local BackupPresetPath = DataPath .. "BackupPresets.tgdata"

local magicWord = 0x7454 -- "Tt"
local maxEmbedSize = 256
local maxEmbedPartCt = maxEmbedSize * maxEmbedSize - 2 -- 65536 minus 2 for header and footer
local MaxPresetSize = maxEmbedPartCt * 8 -- 512kib (only applies to embedding) excluding header and footer
local MaxPasses = 32

local function GetDefaultLayer()
	return { type = elem.DEFAULT_PT_SAND, thickness = 30, variation = 5, mode = 1 }
end

local function GetDefaultPass()
	return { bottom = 40, layers = { GetDefaultLayer(), }, settleTime = 60 }
end

local presetModeNames = {
	"Uniform",
	"Padded",
	"Veins",
	"Replace",
}

local presetModeShortNames = {
	"Uni.",
	"Pad.",
	"Vein",
	"Rep.",
}

-- Contains default values as well as the fields themselves
local presetModeFields = {
	{
		type = elem.DEFAULT_PT_SAND,
		mode = 1,
		thickness = 30,
		variation = 5, 
	},
	{
		type = elem.DEFAULT_PT_SAND,
		mode = 2,
		thickness = 30,
		variation = 5, 
	},
	{
		type = elem.DEFAULT_PT_SAND, 
		mode = 3, 
		minY = 15, 
		maxY = 20, 
		width = 120, 
		height = 3, 
		veinCount = 15
	},
	{
		type = elem.DEFAULT_PT_GOLD,
		mode = 4, 
		oldType = elem.DEFAULT_PT_BMTL,
		percent = 100,
		inExisting = false,
		inLayer = true,
		preserveProps = false,
	}
}

-- Never narrow the ranges between minor updates
local presetModeFieldConstraints = {
	{
		{ prop = "thickness", type = "number", text = "Thickness", min = "-600", max = "600", fraction = true },
		{ prop = "variation", type = "number", text = "Variation", min = "0", max = "600", fraction = true }
	},
	{
		{ prop = "thickness", type = "number", text = "Thickness", min = "-600", max = "600", fraction = true },
		{ prop = "variation", type = "number", text = "Variation", min = "0", max = "600", fraction = true }
	},
	{
		{ prop = "minY", type = "number", text = "Min Y", min = "-600", max = "600", fraction = true },
		{ prop = "maxY", type = "number", text = "Max Y", min = "-600", max = "600", fraction = true },
		{ prop = "width", type = "number", text = "Vein Width", min = "0", max = "600", fraction = true },
		{ prop = "height", type = "number", text = "Vein Height", min = "0", max = "600", fraction = true },
		{ prop = "veinCount", type = "number", text = "Vein Count", min = "0", max = "10000", fraction = false },
	},
	{
		{ prop = "oldType", type = "element", text = "To Replace" },
		{ prop = "percent", type = "number", text = "Percent", min = "0", max = "100", fraction = true },
		{ prop = "inExisting", type = "boolean", text = "Replace Existing" },
		{ prop = "inLayer", type = "boolean", text = "Replace in Layer" },
		{ prop = "preserveProps", type = "boolean", text = "Keep Old Properties" },
	}
}

local function resetLayerMode(layer)
	local template = presetModeFields[layer.mode]
	for k,j in pairs(template) do
		if not layer[k] then
			layer[k] = template[k]
		end
	end
	for k,j in pairs(layer) do
		if not template[k] then
			layer[k] = nil
		end
	end
end

-- Creates a copy of the table as a new object
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

-- Sorts the keys of the table and returns them sorted alphabetically in a sequence
local function SortKeysAlphabetical(toSort)
	local sequence = {}
	for i,j in pairs(toSort) do
		table.insert(sequence, i)
	end
	table.sort(sequence)
	return sequence
	-- Cook & eat sequence
end

local factoryPresets = {
	["Basic Lakes"] = '{"versionMinor":0, "versionMajor":1, "passes":[{"bottom":40, "layers":[{"type":5, "variation":5, "mode":1, "thickness":10}, {"type":47, "variation":5, "mode":1, "thickness":10}, {"type":30, "variation":5, "mode":1, "thickness":10}, {"minY":15, "mode":3, "maxY":20, "type":133, "width":120, "height":3, "veinCount":15}, {"type":5, "variation":5, "mode":1, "thickness":10}, {"minY":15, "mode":3, "maxY":35, "type":73, "width":80, "height":3, "veinCount":20}, {"type":44, "variation":5, "mode":2, "thickness":10}, {"minY":30, "mode":3, "maxY":30, "type":27, "width":60, "height":15, "veinCount":6}], "settleTime":80}, {"settleTime":160, "bottom":160, "layers":[{"type":20, "variation":3, "mode":1, "thickness":2}], "addGravityToSolids":1}]}',
	["'Splodeyland"] = "{\"versionMinor\":0, \"versionMajor\":1, \"passes\":[{\"addGravityToSolids\":true, \"bottom\":4, \"layers\":[{\"type\":0, \"variation\":5, \"mode\":1, \"thickness\":30}, {\"minY\":-10, \"veinCount\":6, \"maxY\":5, \"type\":70, \"mode\":3, \"height\":20, \"width\":120}, {\"type\":70, \"variation\":10, \"mode\":1, \"thickness\":20}, {\"width\":15, \"minY\":15, \"maxY\":20, \"type\":165, \"height\":15, \"mode\":3, \"veinCount\":15}], \"settleTime\":70}, {\"bottom\":4, \"layers\":[{\"width\":120, \"minY\":30, \"maxY\":50, \"type\":5, \"height\":120, \"mode\":3, \"veinCount\":3}, {\"minY\":-70, \"width\":20, \"maxY\":20, \"veinCount\":35, \"height\":180, \"mode\":3, \"type\":70}], \"settleTime\":0}, {\"bottom\":30, \"layers\":[{\"width\":7, \"type\":140, \"maxY\":20, \"veinCount\":1, \"mode\":3, \"height\":400, \"minY\":15}], \"settleTime\":0}, {\"settleTime\":200, \"bottom\":80, \"layers\":[{\"type\":65, \"variation\":5, \"mode\":2, \"thickness\":15}, {\"type\":41, \"variation\":5, \"mode\":1, \"thickness\":10}, {\"type\":69, \"variation\":35, \"mode\":2, \"thickness\":0}, {\"type\":139, \"variation\":5, \"mode\":1, \"thickness\":10}, {\"type\":7, \"variation\":35, \"mode\":1, \"thickness\":0}, {\"width\":80, \"minY\":15, \"maxY\":20, \"type\":8, \"height\":20, \"mode\":3, \"veinCount\":5}], \"addGravityToSolids\":true}, {\"bottom\":40, \"layers\":[{\"mode\":4, \"oldType\":5, \"type\":19, \"percent\":100, \"inExisting\":true, \"inLayer\":false}], \"settleTime\":0}]}",
	["Caves"] = "{\"versionMinor\":0, \"versionMajor\":1, \"passes\":[{\"bottom\":4, \"layers\":[{\"type\":190, \"variation\":5, \"mode\":1, \"thickness\":85}, {\"type\":67, \"variation\":5, \"mode\":1, \"thickness\":65}, {\"type\":5, \"variation\":5, \"mode\":1, \"thickness\":20}, {\"type\":155, \"variation\":5, \"mode\":1, \"thickness\":10}, {\"width\":120, \"minY\":15, \"maxY\":60, \"type\":133, \"height\":3, \"mode\":3, \"veinCount\":15}, {\"minY\":140, \"veinCount\":20, \"maxY\":180, \"type\":187, \"mode\":3, \"height\":3, \"width\":80}, {\"minY\":15, \"width\":100, \"maxY\":200, \"veinCount\":30, \"height\":3, \"mode\":3, \"type\":73}, {\"minY\":0, \"veinCount\":6, \"maxY\":30, \"type\":170, \"mode\":3, \"height\":3, \"width\":120}, {\"width\":200, \"type\":0, \"maxY\":120, \"veinCount\":15, \"mode\":3, \"height\":40, \"minY\":60}, {\"minY\":60, \"veinCount\":15, \"maxY\":120, \"type\":0, \"mode\":3, \"height\":80, \"width\":20}], \"settleTime\":120}, {\"bottom\":4, \"layers\":[{\"width\":15, \"minY\":120, \"maxY\":160, \"type\":67, \"height\":100, \"mode\":3, \"veinCount\":15}, {\"minY\":20, \"veinCount\":15, \"maxY\":40, \"type\":190, \"mode\":3, \"height\":100, \"width\":15}], \"settleTime\":0}, {\"bottom\":4, \"layers\":[{\"type\":190, \"variation\":10, \"mode\":1, \"thickness\":40}, {\"type\":0, \"variation\":10, \"mode\":2, \"thickness\":100}, {\"type\":86, \"variation\":10, \"mode\":1, \"thickness\":30}, {\"minY\":60, \"veinCount\":15, \"maxY\":90, \"type\":2, \"mode\":3, \"height\":10, \"width\":120}, {\"minY\":80, \"veinCount\":15, \"maxY\":80, \"type\":86, \"mode\":3, \"height\":1, \"width\":180}], \"settleTime\":30}, {\"bottom\":4, \"layers\":[{\"width\":4, \"minY\":180, \"maxY\":190, \"type\":114, \"height\":4, \"mode\":3, \"veinCount\":200}], \"settleTime\":60}, {\"bottom\":40, \"layers\":[{\"oldType\":86, \"inExisting\":true, \"type\":0, \"percent\":100, \"mode\":4, \"inLayer\":false}], \"settleTime\":60}]}",
	["Dud"] = "{\"versionMinor\":1, \"versionMajor\":1, \"passes\":[{\"bottom\":4, \"layers\":[{\"type\":190, \"varition\":5, \"mode\":1, \"thickness\":85}, {\"type\":67, \"variation\":5, \"mode\":1, \"thickness\":65}, {\"type\":5, \"variation\":5, \"mode\":1, \"thickness\":20}, {\"type\":155, \"variation\":5, \"mode\":1, \"thickness\":10}, {\"width\":120, \"minY\":15, \"maxY\":60, \"type\":133, \"height\":3, \"mode\":3, \"veinCount\":15}, {\"minY\":140, \"veinCount\":20, \"maxY\":180, \"type\":187, \"mode\":3, \"height\":3, \"width\":80}, {\"minY\":15, \"width\":100, \"maxY\":200, \"veinCount\":30, \"height\":3, \"mode\":3, \"type\":73}, {\"minY\":0, \"veinCount\":6, \"maxY\":30, \"type\":170, \"mode\":3, \"height\":3, \"width\":120}, {\"width\":200, \"type\":0, \"maxY\":120, \"veinCount\":15, \"mode\":3, \"height\":40, \"minY\":60}, {\"minY\":60, \"veinCount\":15, \"maxY\":120, \"type\":0, \"mode\":3, \"height\":80, \"width\":20}], \"settleTime\":120}, {\"bottom\":4, \"layers\":[{\"width\":15, \"minY\":120, \"maxY\":160, \"type\":67, \"height\":100, \"mode\":3, \"veinCount\":15}, {\"minY\":20, \"veinCount\":15, \"maxY\":40, \"type\":190, \"mode\":3, \"height\":100, \"width\":15}], \"settleTime\":0}, {\"bottom\":4, \"layers\":[{\"type\":190, \"variation\":10, \"mode\":1, \"thickness\":40}, {\"type\":0, \"variation\":10, \"mode\":2, \"thickness\":100}, {\"type\":86, \"variation\":10, \"mode\":1, \"thickness\":30}, {\"minY\":60, \"veinCount\":15, \"maxY\":90, \"type\":2, \"mode\":3, \"height\":10, \"width\":120}, {\"minY\":80, \"veinCount\":15, \"maxY\":80, \"type\":86, \"mode\":3, \"height\":1, \"width\":180}], \"settleTime\":30}, {\"bottom\":4, \"layers\":[{\"width\":4, \"minY\":180, \"maxY\":190, \"type\":114, \"height\":4, \"mode\":3, \"veinCount\":200}], \"settleTime\":60}, {\"bottom\":40, \"layers\":[{\"oldType\":86, \"inExisting\":true, \"type\":0, \"percent\":100, \"mode\":4, \"inLayer\":false}], \"settleTime\":60}]}",
}

local function removeFileExtension(filename)
	return string.gsub(filename, "(.+)%..-$", "%1")
end

local function initializeFileSystem()
	-- Create missing directories
	if not fs.exists(DataPath) then
		fs.makeDirectory(DataPath)
	end
	if not fs.exists(PresetPath) then
		local f = io.open(PresetPath, "w")
		f:write("{}")
		f:close()
	end

	-- Check for old TerraGen path
	if fs.exists(OldDataPath) then
		tpt.message_box("Thank you!...", "Thank you for being insane enough to have used Territect while it was still called TerraGen.\nHowever, the data folder has been migrated - if you're smart enough to have used that old version of the script before it was released, then you're smart enough to copy all the files in the 'TerraGen' folder in your TPT data folder to the newly-created 'Territect' folder and delete the old folder.")
	end
	-- I'm too lazy to implement an automatic migration system so I've opted for a nerd-powered approach instead
end

initializeFileSystem()

loadedPresets = {}
local selectedFolder = nil
local selectedPreset = nil

local function saveChanges()
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



-- Preset data embedding


local function checksum(values)
	local sum = 0
	for i = 1, #values do 
		if i % 2 == 1 then
			-- Weird checksum that works well enough
			sum = bit.bxor(sum, (values[i] + (values[i + 1] or 0) * 0x100) * 45823) % 65536
		end
	end
	return sum
end

function generatePresetChunks()
	local presetDataClump = {
		name = selectedPreset,
		data = loadedPresets[selectedFolder][selectedPreset]
	}
	local stringData = json.stringify(presetDataClump)
	-- Encode preset data in DMND particles
	local dataToEncode = {}
	for i = 1, #stringData do
		local c = stringData:sub(i,i)
		dataToEncode[i] = string.byte(c)
	end
	local dataChunks = {}
	local chunkSize = 8 -- Number of bytes of data to be stored in each particle
	local sum = checksum(dataToEncode) -- Checksum to guarantee integrity of encoded data
	for i = 1, #dataToEncode do
		local chunkIndex = math.floor((i - 1) / chunkSize) + 1
		local partIndex = (i - 1) % chunkSize + 1
		if partIndex == 1 then
			dataChunks[chunkIndex] = {}
		end
		dataChunks[chunkIndex][partIndex] = dataToEncode[i]
	end
	return dataChunks, sum
end

function createEmbedParticle(x, y, ctype, life, tmp, tmp2, vtmp3, vtmp4)
	if sim.pmap(x, y) then sim.partKill(sim.pmap(x, y)) end
	local part = sim.partCreate(-3, x, y, elem.DEFAULT_PT_DMND)
	sim.partProperty(part, "ctype", ctype)
	sim.partProperty(part, "life", life)
	sim.partProperty(part, "tmp", tmp)
	sim.partProperty(part, "tmp2", tmp2)
	sim.partProperty(part, tmp3, vtmp3)
	sim.partProperty(part, tmp4, vtmp4)
end

function embedPreset(chunks, x, y, width, height, sum)

	-- Blank data particles
	for i = 0, width - 1 do
		for j = 0, height - 1 do
			createEmbedParticle(x + i, y + j, 
			0, 0, 0, 0, 
			magicWord, -- "Tt" magic word used by data particles
			2 * (i == 0 and 0 or 1) + 4 * (j == 0 and 0 or 1)) -- Navigation indicator
			-- 2: Travel rightwards
			-- 4: Travel upwards
		end
	end

	createEmbedParticle(x, y, 
		sum, -- Checksum
		#chunks, -- Number of chunks (particles)
		width, height, -- tmp and tmp2
		magicWord, -- "Tt" magic word used by data particles
		1) -- Navigation indicator
	local maxj = 0
	for j,k in pairs(chunks) do
		createEmbedParticle(x + (j % width), y + math.floor(j / width), 
			(k[1] or 0) + (k[2] or 0) * 0x100, 
			(k[3] or 0) + (k[4] or 0) * 0x100, 
			(k[5] or 0) + (k[6] or 0) * 0x100, 
			(k[7] or 0) + (k[8] or 0) * 0x100, 
			magicWord, -- "Tt" magic word used by data particles
			2 * (j % width == 0 and 0 or 1) + 4 * (math.floor(j / width) == 0 and 0 or 1)) -- Navigation indicator
			-- 2: Travel rightwards
			-- 4: Travel upwards
		maxj = j + 1
	end
	createEmbedParticle(x + (maxj % width), y + math.floor(maxj / width), 
		0, 0, 0, 0, 
		magicWord, -- "Tt" magic word used by data particles
		8 + 2 * (maxj % width == 0 and 0 or 1) + 4 * (math.floor(maxj / width) == 0 and 0 or 1)) -- Navigation indicator

	-- for l = 0, width * height do
	-- 	local dataPart = sim.partCreate(-1, x + (l % width), y + math.floor(l / width), elem.DEFAULT_PT_DMND)
	-- 	sim.partProperty(dataPart, tmp3, magicWord) -- "Tt" magic word used by data particles
	-- 	sim.partProperty(dataPart, tmp4, 4) -- Indicates that this is a filler particle
	-- 	maxj = l + 1
	-- end
end


local embeddingPreset
local embedData
local embedSum

local embedBoxX = 10
local embedBoxY = 10
local embedBoxWidth = 50
local embedBoxHeight = 50

local embedWindow = Window:new(1000, 0, 0 ,0)

local embedDataFits = true;


embedWindow:onDraw(function()

	local particleCount = #embedData + 2
	local embedSize = embedBoxWidth * embedBoxHeight

	embedDataFits = particleCount <= embedSize

	anyObstructingParticles = false
	for i = 1, embedSize do
		local cX, cY = embedBoxX + (i % embedBoxWidth), embedBoxY + math.floor(i / embedBoxHeight)
		local id = sim.partID(cX, cY)
		if id ~= nil then
			anyObstructingParticles = true
			break
		end
	end

	local canPlace = embedDataFits
	local r = embedDataFits and 0 or 255
	local g = embedDataFits and 255 or 0

	graphics.drawRect(embedBoxX, embedBoxY, embedBoxWidth, embedBoxHeight, 200, 200, 200)

	graphics.fillRect(embedBoxX, embedBoxY, embedBoxWidth, embedBoxHeight, 0, 0, 0, 127)

	graphics.fillRect(embedBoxX, embedBoxY, embedBoxWidth, math.floor(particleCount / embedBoxWidth), r, g, 0, 127)
	graphics.fillRect(embedBoxX, embedBoxY + math.floor(particleCount / embedBoxWidth), particleCount % embedBoxWidth, 1, r, g, 0, 127)

	local warningY = 345

	if not embedDataFits then
		graphics.drawText(16, warningY, "Warning: The current box size is too small to fit the preset data.", 255, 0, 0)
		warningY = warningY - 15
	end

	if anyObstructingParticles then
		graphics.drawText(16, warningY, "Warning: Particles under the box will be overwritten.", 255, 127, 0)
		warningY = warningY - 15
	end


	graphics.drawText(16, 360, "Click to place. Scroll to adjust width (shift/ctrl for one dimension). Shift to move box precisely. Right-click to cancel.", 255, 255, 0)
end)

embedWindow:onMouseDown(function(x, y, button)
	if not embedDataFits then
		return
	end

	if button == 1 then -- Lmb
		embedPreset(embedData, embedBoxX, embedBoxY, embedBoxWidth, embedBoxHeight, embedSum)
	elseif button == 3 then -- Rmb

	end

	embeddingPreset = false
	interface.closeWindow(embedWindow)
end)

local ctrlHeld = false
local shiftHeld = false

embedWindow:onMouseMove(function(x, y, dx, dy)
	if shiftHeld then
		embedBoxX, embedBoxY = embedBoxX + dx * 0.2, embedBoxY + dy * 0.2
	else
		embedBoxX, embedBoxY = sim.adjustCoords(x, y)
	end

end)

embedWindow:onKeyPress(function(key, scan, r, shift, ctrl, alt)
	if scan == 225 or scan == 229 then
		shiftHeld = true
	end

	if scan == 224 or scan == 228 then
		ctrlHeld = true
	end
end)

embedWindow:onKeyRelease(function(key, scan, r, shift, ctrl, alt)
	if scan == 225 or scan == 229 then
		shiftHeld = false
	end

	if scan == 224 or scan == 228 then
		ctrlHeld = false
	end
end)

embedWindow:onMouseWheel(function(x, y, d)
	if not shiftHeld then
		embedBoxHeight = math.min(math.max(embedBoxHeight + d, 1), maxEmbedSize)
	end

	if not ctrlHeld then
		embedBoxWidth = math.min(math.max(embedBoxWidth + d, 1), maxEmbedSize)
	end
end)

event.register(event.tick, function()
    if embeddingPreset then
		interface.showWindow(embedWindow)
	end
end)

-- Reading embedded preset data

-- Check the particle under the cursor for the territect magic number in tmp3

local embedReading = {
	foundEmbedded = false,
	embedReadError = false,
	errorPosition = false,
	errorX = -1,
	errorY = -1,
	embeddedX = -1,
	embeddedY = -1,
	embeddedW = -1,
	embeddedH = -1,
	embeddedMessage,
	embeddedPreset,
	embeddedHeaderID = -1, -- Used to prevent the same preset from being read several times on concurrent frames
}

event.register(event.tick, function()
	local px, py = sim.adjustCoords(tpt.mousex, tpt.mousey)
	local cursorPart = sim.pmap(px, py)

	local readError
	local refreshError = false

	if not (cursorPart and sim.partProperty(cursorPart, tmp3) == magicWord) then
		embedReading.embeddedHeaderID = -1
		embedReading.foundEmbedded = false
		return
	else
		embedReading.foundEmbedded = true

		local guideValue = 0
		local guidePart
		local gx = px
		local gy = py

		-- Uses the information in particles' tmp4 values to navigate the head at gx, gy towards the top right header particle.
		-- 1: Header particle
		-- 2: Go right
		-- 4: Go up
		-- 8: Footer particle
		
		local repeatLimit = 10000 
		repeat
			guidePart = sim.pmap(gx, gy)
			-- Ensure the head always stays on a data particle
			if not guidePart then
				readError = "Preset data ended before expected"
			elseif sim.partProperty(guidePart, "type") ~= elem.DEFAULT_PT_DMND or sim.partProperty(guidePart, tmp3) ~= magicWord then
				readError = "Found foreign particle while scanning preset data"
			end
			if readError then
				embedReading.embeddedHeaderID = -1
				embedReading.errorPosition = true
				embedReading.errorX = gx
				embedReading.errorY = gy
				refreshError = true
				goto embedReadingError
			end
			guideValue = sim.partProperty(guidePart, tmp4)
			if bit.band(guideValue, 0x2) ~= 0 then
				gx = gx - 1
			end
			if bit.band(guideValue, 0x4) ~= 0 then
				gy = gy - 1
			end
			repeatLimit = repeatLimit - 1
		until guideValue == 1 or repeatLimit == 0

		if repeatLimit == 0 then
			embedReading.errorPosition = false
			readError = "Could not find header particle"
			refreshError = true
			goto embedReadingError
		end

		embedReading.embeddedX = gx
		embedReading.embeddedY = gy
		local headerPart = sim.pmap(gx, gy) -- We know this is a valid data part because of the previous steps

		if embedReading.embeddedHeaderID ~= headerPart then
			refreshError = true
			embedReading.embeddedHeaderID = headerPart
			local headerChecksum = sim.partProperty(headerPart, "ctype")
			local chunkCount = sim.partProperty(headerPart, "life")
			local width = sim.partProperty(headerPart, "tmp")
			local height = sim.partProperty(headerPart, "tmp2")

			embedReading.embeddedW = width
			embedReading.embeddedH = height

			local chunks = {}
	
			-- Read data from particles
			for i = 1, chunkCount do
				local cx, cy = gx + (i % width), gy + math.floor(i / width)
				local chunkPart = sim.pmap(cx, cy)
	
				-- Ensure the head always stays on a data particle
				if not chunkPart then
					readError = "Preset data ended before expected"
				elseif sim.partProperty(chunkPart, "type") ~= elem.DEFAULT_PT_DMND or sim.partProperty(chunkPart, tmp3) ~= magicWord then
					readError = "Found foreign particle while scanning preset data"
				end
				if readError then
					embedReading.errorPosition = true
					embedReading.errorX = cx
					embedReading.errorY = cy
					goto embedReadingError
				end
				
				-- Extract text data from particle data
				local bytes = {
					sim.partProperty(chunkPart, "ctype"),
					sim.partProperty(chunkPart, "life"),
					sim.partProperty(chunkPart, "tmp"),
					sim.partProperty(chunkPart, "tmp2"),
				}
	
				local chunk = {
					string.char(bit.band(bytes[1], 0x00FF) / 0x0001),
					string.char(bit.band(bytes[1], 0xFF00) / 0x0100),
					string.char(bit.band(bytes[2], 0x00FF) / 0x0001),
					string.char(bit.band(bytes[2], 0xFF00) / 0x0100),
					string.char(bit.band(bytes[3], 0x00FF) / 0x0001),
					string.char(bit.band(bytes[3], 0xFF00) / 0x0100),
					string.char(bit.band(bytes[4], 0x00FF) / 0x0001),
					string.char(bit.band(bytes[4], 0xFF00) / 0x0100),
				}
				table.insert(chunks, table.concat(chunk))
				if i >= maxEmbedPartCt then
					embedReading.errorPosition = false
					readError = "Preset is above the maximum size of " .. maxEmbedPartCt .. " particles."
					goto embedReadingError
				end
			end
			-- No errors past this point are positional
			embedReading.errorPosition = false
			embedReading.errorX = -1
			embedReading.errorY = -1

			-- Convert chunks into text data
			local presetText = table.concat(chunks)

			-- Checksum
			local checksumTable = {}
			for i = 1, #presetText do
				local c = presetText:sub(i,i)
				checksumTable[i] = string.byte(c)
			end
			local sum = checksum(checksumTable) -- Checksum to guarantee integrity of encoded data

			if sum ~= headerChecksum then
				readError = "Checksum invalid - data may be corrupted or tampered with."
				goto embedReadingError
			end

			-- Verify preset data contains JSON containing a valid preset
			local validJson, table = pcall(json.parse, presetText)

			if not validJson then
				readError = "Preset data unreadable due to error in JSON formatting."
				goto embedReadingError
			end

			if not table.data then
				readError = "Preset data could not be found."
				goto embedReadingError
			end
			local validPresetJson, presetTable = pcall(json.parse, table.data)

			if not validPresetJson then
				readError = "Preset data unreadable due to error in JSON formatting."
				goto embedReadingError
			end

			local validPreset, message = verifyPresetIntegrity(presetTable)
			if validPreset then
				-- Hooray!
				if #message > 0 then
					embedReading.embeddedMessage = "Download \"" .. table.name .. "\" Territect preset (" .. #message .. " warnings)"
				else
					embedReading.embeddedMessage = "Download \"" .. table.name .. "\" Territect preset"
				end
			else
				readError = message
				goto embedReadingError
			end
		end
	end

	-- embedReading.embedReadError = false

	::embedReadingError::

	-- print(readError)

	if refreshError then
		if readError then
			if embedReading.errorPosition then
				embedReading.embeddedX = embedReading.errorX
				embedReading.embeddedY = embedReading.errorY
			end
			embedReading.embedReadError = true
			embedReading.embeddedMessage = readError
		else
			embedReading.embedReadError = false
			-- embedReading.embeddedMessage = "No errors found."

			embedReading.errorX = -1
			embedReading.errorY = -1
		end
	end

	if embedReading.foundEmbedded then
		if embedReading.embedReadError then
			if embedReading.errorPosition then
				graphics.drawRect(embedReading.errorX - 2, embedReading.errorY - 2, 5, 5, 255, 0, 0)
			else
				graphics.drawRect(embedReading.embeddedX, embedReading.embeddedY, embedReading.embeddedW, embedReading.embeddedH, 255, 0, 0)
			end
		else
			graphics.drawRect(embedReading.embeddedX, embedReading.embeddedY, embedReading.embeddedW, embedReading.embeddedH, 255, 255, 255)
		end
		graphics.drawText(embedReading.embeddedX, embedReading.embeddedY - 16, embedReading.embeddedMessage, 255, 255, 255)
	end
end)




-- Verify that a table contains a valid preset
function verifyPresetIntegrity(presetData)
	-- We know that preset data within a major version will always be compatible with future versions
	-- and older versions may be able to run some presets from newer versions
	-- However, version 1.0 won't know the major changes made in 2.0, so it will reject presets from that far in the future
	local warnings = {}
	if presetData.versionMajor then
		if presetData.versionMajor <= versionMajor then
			if not presetData.versionMinor then
				return false, "This preset is missing a minor version number."
			end
			if presetData.versionMinor > versionMinor then
				table.insert(warnings, { "newerVersion", presetData.versionMajor, presetData.versionMinor })
			end
			if not presetData.passes then
				return false, "This preset is missing instructions for Territect. (inside 'passes')"
			end
			for i, j in pairs(presetData.passes) do
				-- TODO: Create some sort of pattern to make this more expandable?
				if not j.bottom then
					return false, "Pass " .. i .. " is missing a 'bottom' value"
				end
				if not j.settleTime then
					return false, "Pass " .. i .. " is missing a 'settleTime' value"
				end
				if not j.layers then
					return false, "Pass " .. i .. " does not have an entry for layers"
				end
				for k, l in pairs(j.layers) do
					local mode = l.mode
					if not mode then
						return false, "Layer " .. k .. " in Pass " .. i .. " is missing a 'mode' value"
					end
					if not l.type then
						return false, "Layer " .. k .. " in Pass " .. i .. " is missing a 'type' value"
					end
					-- TODO: Check if 'type' is valid
					if not presetModeFieldConstraints[mode] then
						return false, "Layer " .. k .. " in Pass " .. i .. " has an invalid 'mode' value"
					end
					for m, n in pairs(presetModeFieldConstraints[mode]) do
						local prop = n.prop
						local pval = l[prop]
						if pval == nil then
							table.insert(warnings, { "missingLayerVal", k, i, n.prop })
							-- Unnecessary: missing values can be replaced with their defaults
							-- return false, "Layer " .. k .. " in Pass " .. i .. " is missing a '" .. n.prop .. "' value"
						elseif n.type == "number" then
							local asNumber = tonumber(pval)
							if not asNumber or asNumber < tonumber(n.min) or asNumber > tonumber(n.max) then
								return false, "Property" .. prop .. " of Layer " .. k .. " in Pass " .. i .. " is outside the range of acceptable values (number between " .. n.min .. " and " .. n.max .. ") at '" .. pval .. "'"
							end
						elseif n.type == "boolean" then
							if not pval == "true" and not pval == "false" then
								return false, "Property" .. prop .. " of Layer " .. k .. " in Pass " .. i .. " is outside the range of acceptable values (boolean) at '" .. pval .. "'"
							end
						elseif n.type == "element" then
							local asNumber = tonumber(pval)
							if not asNumber or not pcall(elements.property, asNumber, "Name") then
								return false, "Property" .. prop .. " of Layer " .. k .. " in Pass " .. i .. " is outside the range of acceptable values (element) at '" .. pval .. "'"
							end
						end
					end

				end
			end
		else
			return false, "This preset is from a much newer version (v" .. presetData.versionMajor .. "." .. presetData.versionMinor .. "), so we don't know how to read it."
		end
	else
		return false, "This preset is missing a major version number, so we don't know how to read it."
	end
	return true, warnings
end

-- TODO: Repair presets that are missing non-important information


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

-- Creates a dropdown window from the choices provided
function createDropdown(options, x, y, width, height, action)
	local dropdownWindow = Window:new(x, y, width, (height - 1) * #options + 1)
	local buttonChoices = {}
	for i,j in pairs(options) do
		local dropdownButton = Button:new(0, (height - 1) * (i - 1), width, height, j)
		dropdownButton:action(
			function(sender)
				action(buttonChoices[sender])
				interface.closeWindow(dropdownWindow)
			end)
		dropdownButton:text(j)
		buttonChoices[dropdownButton] = i
		dropdownWindow:addComponent(dropdownButton)
	end
	dropdownWindow:onTryExit(function()
		interface.closeWindow(dropdownWindow)
	end)
	interface.showWindow(dropdownWindow)
end




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
    graphics.drawText(genDropDownX + 3, modifiedY + 3, "Territect", 255, 255, 255)
end)


-- Main window
local terraGenWindowWidth = 300
local terraGenWindowHeight = 260
local terraGenWindow = Window:new(-1, -1, terraGenWindowWidth, terraGenWindowHeight)
terraGenWindow:onTryExit(function()
	interface.closeWindow(terraGenWindow)
end)


-- Code for preset editor further below
local presetEditorWindowWidth = 470
local presetEditorWindowHeight = 260
local presetEditorWindow = Window:new(-1, -1, presetEditorWindowWidth, presetEditorWindowHeight)
local workingPreset = nil

local versionText = "Territect v" .. versionMajor .. "." .. versionMinor
local versionLabelSize = graphics.textSize(warningLabel)
local versionLabel = Label:new(terraGenWindowWidth / 2 - versionLabelSize / 2, 5, versionLabelSize, 16, versionText)

-- Folder selector box
local selectorBoxPadding = 10
local selectorBoxWidth = terraGenWindowWidth / 2 - selectorBoxPadding * 2
local selectorBoxHeight = 91
local selectorBoxY = selectorBoxPadding + 15
local folderSelectorBoxX = selectorBoxPadding
local folderSelectorBox = Button:new(folderSelectorBoxX, selectorBoxY, selectorBoxWidth, selectorBoxHeight)
folderSelectorBox:enabled(false)

function tryAddCopyNumber(table, name)
	if not table[name] then return name, -1 end
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

function isNameValid(table, name, itemtype)
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
local newFolderButton = Button:new(folderSelectorBoxX, selectorBottom, selectorBoxWidth / 2 - 1, 16, "New")
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
    end)
terraGenWindow:addComponent(newFolderButton)

-- Rename folder button
local renameFolderButton = Button:new(folderSelectorBoxX + selectorBoxWidth / 2 + 1, selectorBottom, selectorBoxWidth / 2 - 1, 16, "Rename")
renameFolderButton:action(
    function()
		local name = tpt.input("Rename Folder", "New name:", selectedFolder) 
		if #name == 0 or name == selectedFolder then return end
		local validName, message = isNameValid(loadedPresets, name, "folder")
		if validName then
			loadedPresets[name], loadedPresets[selectedFolder] = loadedPresets[selectedFolder], loadedPresets[name]
			selectedFolder = name
			refreshWindowFolders()
			refreshWindowPresets()
			updateButtons()

			saveChanges()
		else
			tpt.message_box("Invalid Name", message)
		end
    end)
terraGenWindow:addComponent(renameFolderButton)

-- Delete folder button
local deleteFolderButton = Button:new(folderSelectorBoxX, selectorBottom + 18, selectorBoxWidth / 2 - 1, 16, "Delete")
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
	end)

-- Clone folder button
local cloneFolderButton = Button:new(folderSelectorBoxX + selectorBoxWidth / 2 + 1, selectorBottom + 18, selectorBoxWidth / 2 - 1, 16, "Clone")
cloneFolderButton:action(
	function()
		local newName, num = tryAddCopyNumber(loadedPresets, selectedFolder)
		if newName == nil then
			tpt.message_box("Cloning Failed", "Cloning failed. Reason: Too many copies with the same name.")
			return
		end
		-- if newName == nil then newName = "New Preset" end
		loadedPresets[newName] = loadedPresets[selectedFolder]
		refreshWindowFolders()
		refreshWindowPresets()

		saveChanges()
	end)
terraGenWindow:addComponent(cloneFolderButton)

local presetSelectorBoxX = terraGenWindowWidth - selectorBoxPadding - selectorBoxWidth
local presetSelectorBox = Button:new(presetSelectorBoxX, selectorBoxY, selectorBoxWidth, selectorBoxHeight)
presetSelectorBox:enabled(false)

-- New preset button
local newPresetButton = Button:new(presetSelectorBoxX, selectorBottom, selectorBoxWidth / 3 - 1, 16, "New")
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
terraGenWindow:addComponent(newPresetButton)

local editPresetButton = Button:new(presetSelectorBoxX + selectorBoxWidth / 3 + 1, selectorBottom, selectorBoxWidth / 3 - 1, 16, "Edit")
editPresetButton:action(
function()
	setupEditorWindow()
	interface.showWindow(presetEditorWindow)

	saveChanges()
end)
terraGenWindow:addComponent(editPresetButton)

local renamePresetButton = Button:new(presetSelectorBoxX + selectorBoxWidth / 3 * 2 + 2, selectorBottom, selectorBoxWidth / 3 - 1, 16, "Rename")
renamePresetButton:action(
function()
	local name = tpt.input("Rename Preset", "New name:", selectedPreset) 
		if #name == 0 or name == selectedPreset then return end
		local validName, message = isNameValid(loadedPresets, name, "folder")
		if validName then
			loadedPresets[selectedFolder][name], loadedPresets[selectedFolder][selectedPreset] = loadedPresets[selectedFolder][selectedPreset], loadedPresets[selectedFolder][name]
			selectedPreset = name
			refreshWindowPresets()
			updateButtons()

			saveChanges()
		else
			tpt.message_box("Invalid Name", message)
		end
end)
terraGenWindow:addComponent(renamePresetButton)

local deletePresetButton = Button:new(presetSelectorBoxX, selectorBottom + 18, selectorBoxWidth / 3 - 1, 16, "Delete")
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
terraGenWindow:addComponent(deletePresetButton)

local clonePresetButton = Button:new(presetSelectorBoxX + selectorBoxWidth / 3 + 1, selectorBottom + 18, selectorBoxWidth / 3 - 1, 16, "Clone")
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
terraGenWindow:addComponent(clonePresetButton)

local exportPresetButton = Button:new(presetSelectorBoxX + selectorBoxWidth / 3 * 2 + 2, selectorBottom + 18, selectorBoxWidth / 3 - 1, 16, "Im/Exp.")
exportPresetButton:action(
function()
	local factory = selectedFolder == "Factory"
	local presetSelected = selectedPreset ~= nil
	local pagePresetName = "..."
	if presetSelected then
		pagePresetName = selectedPreset
	end

	local importExportWindow = Window:new(-1, -1, 300, 200)

	local importExportLabel = Label:new(0, 4, 300, 16, "Import/Export Preset")
	importExportWindow:addComponent(importExportLabel)

	local copyPresetDataButton = Button:new(10, 30, 280, 16, "Copy '" .. pagePresetName ..  "' to clipboard")
	copyPresetDataButton:action(
		function()
			local presetDataClump = {
				name = selectedPreset,
				data = loadedPresets[selectedFolder][selectedPreset]
			}
			tpt.set_clipboard(json.stringify(presetDataClump))
			tpt.message_box("Success", "Copied preset data to clipboard.")
			interface.closeWindow(importExportWindow)
	end)
	importExportWindow:addComponent(copyPresetDataButton)
	copyPresetDataButton:enabled(presetSelected)

	local embedPresetDataButton = Button:new(10, 50, 280, 16, "Embed '" .. pagePresetName .. "' into save")
	embedPresetDataButton:action(
		function()
			local data, sum = generatePresetChunks()
			embeddingPreset = true
			embedData = data;
			embedSum = sum;
			shiftHeld = false;

			interface.closeWindow(importExportWindow)
			interface.closeWindow(terraGenWindow)
		end)
	importExportWindow:addComponent(embedPresetDataButton)
	embedPresetDataButton:enabled(presetSelected)

	local pastePresetDataButton = Button:new(10, 80, 280, 16, "Paste clipboard data in '" .. selectedFolder .. "' as new preset")
	pastePresetDataButton:action(
		function()
			local clipboardData = tpt.get_clipboard()
			local valid, table = pcall(json.parse, clipboardData)
			print(table)

			local newName, num = tryAddCopyNumber(loadedPresets[selectedFolder], table.name)
			if newName == nil then
				tpt.message_box("Cloning Failed", "Cloning failed. Reason: Too many copies with the same name.")
				return
			end
			-- if newName == nil then newName = "New Preset" end
			loadedPresets[selectedFolder][newName] = table.data
			selectedPreset = newName
			refreshWindowFolders()
			refreshWindowPresets()
			
			saveChanges()
			interface.closeWindow(importExportWindow)
	end)
	importExportWindow:addComponent(pastePresetDataButton)

	local overwritePresetDataButton = Button:new(10, 100, 280, 16, "Overwrite '" .. selectedPreset .. "' with clipboard data")
	overwritePresetDataButton:action(
		function()
	end)
	importExportWindow:addComponent(overwritePresetDataButton)

	local cancelPresetDataButton = Button:new(10, 130, 280, 16, "Cancel")

	importExportWindow:addComponent(cancelPresetDataButton)



	interface.showWindow(importExportWindow)
	importExportWindow:onTryExit(function()
		interface.closeWindow(importExportWindow)
	end)

end)
terraGenWindow:addComponent(exportPresetButton)






local extraButtonOffset = selectorBottom + 46
local extraButtonAddWidth = 9
local extraButtonWidth = selectorBoxWidth + extraButtonAddWidth
local userSettingButton = Button:new(folderSelectorBoxX, extraButtonOffset, extraButtonWidth, 16, "Settings")
userSettingButton:action(
function()
	tpt.message_box("Pretend things are getting configured", "Please travel into the future where Reb has implemented the settings screen.")
end)

local helpPageButton = Button:new(presetSelectorBoxX - extraButtonAddWidth, extraButtonOffset, extraButtonWidth, 16, "Help")
helpPageButton:action(
function()
	platform.openLink("https://github.com/Rebmiami/Territect/wiki")
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
		renameFolderButton:enabled(false)
		cloneFolderButton:enabled(true)
		editPresetButton:enabled(loadedPresets[selectedFolder][selectedPreset] ~= nil and devMode == true)
		deletePresetButton:enabled(false)
		clonePresetButton:enabled(false)
		newPresetButton:enabled(false)
		renamePresetButton:enabled(false)
		exportPresetButton:enabled(loadedPresets[selectedFolder][selectedPreset] ~= nil)
	else
		goButton:enabled(loadedPresets[selectedFolder] ~= nil and loadedPresets[selectedFolder][selectedPreset] ~= nil)
		deleteFolderButton:enabled(loadedPresets[selectedFolder] ~= nil)
		renameFolderButton:enabled(loadedPresets[selectedFolder] ~= nil)
		cloneFolderButton:enabled(loadedPresets[selectedFolder] ~= nil)
		editPresetButton:enabled(loadedPresets[selectedFolder] ~= nil and loadedPresets[selectedFolder][selectedPreset] ~= nil)
		deletePresetButton:enabled(loadedPresets[selectedFolder] ~= nil and loadedPresets[selectedFolder][selectedPreset] ~= nil)
		clonePresetButton:enabled(loadedPresets[selectedFolder] ~= nil and loadedPresets[selectedFolder][selectedPreset] ~= nil)
		newPresetButton:enabled(loadedPresets[selectedFolder] ~= nil)
		renamePresetButton:enabled(loadedPresets[selectedFolder] ~= nil and loadedPresets[selectedFolder][selectedPreset] ~= nil)
		exportPresetButton:enabled(loadedPresets[selectedFolder] ~= nil)
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
		sim.edgeMode(1)

		terraGenCoroutine = coroutine.create(runTerraGen)
		terraGenRunning = true
		coroutine.resume(terraGenCoroutine)
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
terraGenWindow:addComponent(deleteFolderButton)

terraGenWindow:addComponent(presetSelectorBox)

terraGenWindow:addComponent(userSettingButton)
terraGenWindow:addComponent(helpPageButton)
terraGenWindow:addComponent(bugReportButton)
terraGenWindow:addComponent(suggestFeatureButton)

terraGenWindow:addComponent(testLabel)
terraGenWindow:addComponent(goButton)
terraGenWindow:addComponent(closeButton)


-- Folder/preset selection buttons are generated below

local selectorPageSize = 6

local folderSelectScroll = 1
local presetSelectScroll = 1

local selectorButtonHeight = 16

-- Scroll through list of folders/presets
terraGenWindow:onMouseWheel(function(x, y, d)
	-- Adjust for window position
	local winW, winH = terraGenWindow:size()
	local adjX, adjY = x - (graphics.WIDTH - winW) / 2, y - (graphics.HEIGHT - winH) / 2

	if adjY > selectorBoxY and adjY < selectorBoxY + selectorBoxHeight then
		if adjX > folderSelectorBoxX and adjX < folderSelectorBoxX + selectorBoxWidth then
			folderSelectScroll = folderSelectScroll - d
			refreshWindowFolders()
		end
		if loadedPresets[selectedFolder] and adjX > presetSelectorBoxX and adjX < presetSelectorBoxX + selectorBoxWidth then
			presetSelectScroll = presetSelectScroll - d
			refreshWindowPresets()
		end
	end
end)

function enforceScrollBounds(isFolders)
	if isFolders then
		local maxScroll = 0
		for i,j in pairs(loadedPresets) do
			maxScroll = maxScroll + 1
		end
		folderSelectScroll = math.max(1, math.min(folderSelectScroll, maxScroll))
	else
		if loadedPresets[selectedFolder] then
			local maxScroll = 0
			for i,j in pairs(loadedPresets[selectedFolder]) do
				maxScroll = maxScroll + 1
			end
			presetSelectScroll = math.max(1, math.min(presetSelectScroll, maxScroll))
		end
	end
end

local windowFolderSelections = {}
function refreshWindowFolders()
	enforceScrollBounds(true)
	for k,j in pairs(windowFolderSelections) do
		terraGenWindow:removeComponent(k)
	end
	windowFolderSelections = {}
	-- local i = 0

	local sorted = SortKeysAlphabetical(loadedPresets)
	local lastVisible = math.min(#sorted, selectorPageSize + folderSelectScroll - 1)

	for k = folderSelectScroll, lastVisible do
		local pos = k - folderSelectScroll
		local j = sorted[k]
		local folderButton = Button:new(folderSelectorBoxX, selectorBoxY + (selectorButtonHeight - 1) * pos, selectorBoxWidth, selectorButtonHeight)
		folderButton:action(
			function()
				selectedPreset = nil
				selectedFolder = windowFolderSelections[folderButton]
				refreshWindowPresets()
				refreshFolderSelectionText()
				updateButtons()
			end
		)
		windowFolderSelections[folderButton] = j
		terraGenWindow:addComponent(folderButton)
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
	enforceScrollBounds(false)
	for k,j in pairs(windowPresetSelections) do
		terraGenWindow:removeComponent(k)
	end
	windowPresetSelections = {}
	if loadedPresets[selectedFolder] then
		local sorted = SortKeysAlphabetical(loadedPresets[selectedFolder])
		local lastVisible = math.min(#sorted, selectorPageSize + presetSelectScroll - 1)

		for k = presetSelectScroll, lastVisible do
			local pos = k - presetSelectScroll
			local j = sorted[k]
			local presetButton = Button:new(presetSelectorBoxX, selectorBoxY + (selectorButtonHeight - 1) * pos, selectorBoxWidth, selectorButtonHeight)
			presetButton:action(
				function()
					selectedPreset = windowPresetSelections[presetButton]
					refreshPresetSelectionText()
					updateButtons()
				end
			)
			windowPresetSelections[presetButton] = removeFileExtension(j)
			terraGenWindow:addComponent(presetButton)
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

local layerPage = 1
local layerPageCount = 1
local layersPerPage = 10

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
    end)
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
    end)
presetEditorWindow:addComponent(deletePassButton)

local movePassLeftButton = Button:new(passSelectorBoxX + 18 * 2, selectorBoxY + 18, passSelectorBoxHeight, passSelectorBoxHeight, "<")
movePassLeftButton:action(
    function()
		workingPreset.passes[selectedPass], workingPreset.passes[selectedPass - 1] = workingPreset.passes[selectedPass - 1], workingPreset.passes[selectedPass]
		selectedPass = selectedPass - 1
		refreshWindowPasses()
		updatePresetButtons()
    end)
presetEditorWindow:addComponent(movePassLeftButton)

local movePassRightButton = Button:new(passSelectorBoxX + 18 * 3, selectorBoxY + 18, passSelectorBoxHeight, passSelectorBoxHeight, ">")
movePassRightButton:action(
    function()
		workingPreset.passes[selectedPass], workingPreset.passes[selectedPass + 1] = workingPreset.passes[selectedPass + 1], workingPreset.passes[selectedPass]
		selectedPass = selectedPass + 1
		refreshWindowPasses()
		updatePresetButtons()
    end)
presetEditorWindow:addComponent(movePassRightButton)

local clonePassButton = Button:new(passSelectorBoxX + 18 * 4, selectorBoxY + 18, passSelectorBoxHeight, passSelectorBoxHeight, "C")
clonePassButton:action(
    function()
		table.insert(workingPreset.passes, selectedPass + 1, CopyTable(workingPreset.passes[selectedPass]))
		selectedPass = selectedPass + 1
		
		refreshWindowPasses()
		updatePresetButtons()
    end)
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
				refreshWindowLayers()
				refreshPassSelectionFade()
				updatePresetButtons()
			end)
		windowPassSelections[passButton] = k
		presetEditorWindow:addComponent(passButton)
	end
	refreshPassSelectionFade()
	refreshWindowLayers()
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


local settleTimeText = "Settle Time (f):"
local settleTimeLabelSize = graphics.textSize(settleTimeText)
local settleTimeLabel = Label:new(passSelectorBoxX + 235, passButtonHeight, settleTimeLabelSize, 16, settleTimeText)
presetEditorWindow:addComponent(settleTimeLabel)


-- Layer selection

local layerTextHeight = passButtonHeight + 18
local layerText = "Layers:"
local layerLabelSize = graphics.textSize(layerText)
local layerLabel = Label:new(presetEditorWindowWidth / 2 - layerLabelSize / 2, layerTextHeight, layerLabelSize, 16, layerText)
presetEditorWindow:addComponent(layerLabel)


local layerButtonHeight = 16
local layerControlHeight = layerTextHeight + 18
local layerSelectorBoxWidth = 100
local layerSelectorBoxX = presetSelectorBoxPadding
local layerSelectorBoxHeight = 15 * layersPerPage + 1
local layerSelectorBox = Button:new(layerSelectorBoxX, layerControlHeight, layerSelectorBoxWidth, layerSelectorBoxHeight)
layerSelectorBox:enabled(false)
presetEditorWindow:addComponent(layerSelectorBox)

local layerPageButtonY = layerControlHeight + layerSelectorBoxHeight - 1
local layerPageButtonWidth = 35
local layerPageLeft = Button:new(layerSelectorBoxX, layerPageButtonY, layerPageButtonWidth, 16, "<")
layerPageLeft:action(
    function()
		layerPage = layerPage - 1
		
		refreshLayerPages()
		updatePresetButtons()
    end)
presetEditorWindow:addComponent(layerPageLeft)

local layerPageLabel = Label:new(layerSelectorBoxX + layerPageButtonWidth, layerPageButtonY, 30, 16)
presetEditorWindow:addComponent(layerPageLabel)

local layerPageRight = Button:new(layerSelectorBoxX + layerSelectorBoxWidth - layerPageButtonWidth, layerPageButtonY, layerPageButtonWidth, 16, ">")
layerPageRight:action(
    function()
		layerPage = layerPage + 1
		
		refreshLayerPages()
		updatePresetButtons()
    end)
presetEditorWindow:addComponent(layerPageRight)


local layerButtonX = layerSelectorBoxX + layerSelectorBoxWidth + 10
local layerButtonYSpacing = 18
local layerButtonWidth = 70
local addLayerButton = Button:new(layerButtonX, layerControlHeight + layerButtonYSpacing * 0, layerButtonWidth, passSelectorBoxHeight, "New")
addLayerButton:action(
    function()
		if selectedLayer then
			table.insert(workingPreset.passes[selectedPass].layers, selectedLayer + 1, GetDefaultLayer())
			selectedLayer = selectedLayer + 1
		else
			table.insert(workingPreset.passes[selectedPass].layers, GetDefaultLayer())
			selectedLayer = #workingPreset.passes[selectedPass].layers
		end
		
		refreshWindowLayers()
		updatePresetLayerButtons()
    end)
presetEditorWindow:addComponent(addLayerButton)

local deleteLayerButton = Button:new(layerButtonX, layerControlHeight + layerButtonYSpacing * 1, layerButtonWidth, passSelectorBoxHeight, "Delete")
deleteLayerButton:action(
    function()
		table.remove(workingPreset.passes[selectedPass].layers, selectedLayer)
		if selectedLayer > #workingPreset.passes[selectedPass].layers then
			selectedLayer = #workingPreset.passes[selectedPass].layers
		end
		if not workingPreset.passes[selectedPass].layers[selectedLayer] then
			selectedLayer = nil
		end
		refreshWindowLayers()
		updatePresetLayerButtons()
    end)
presetEditorWindow:addComponent(deleteLayerButton)

local moveLayerLeftButton = Button:new(layerButtonX, layerControlHeight + layerButtonYSpacing * 2, layerButtonWidth, passSelectorBoxHeight, "Move Up")
moveLayerLeftButton:action(
    function()
		workingPreset.passes[selectedPass].layers[selectedLayer], workingPreset.passes[selectedPass].layers[selectedLayer + 1] = workingPreset.passes[selectedPass].layers[selectedLayer + 1], workingPreset.passes[selectedPass].layers[selectedLayer]
		selectedLayer = selectedLayer + 1
		refreshWindowLayers()
		updatePresetLayerButtons()
    end)
presetEditorWindow:addComponent(moveLayerLeftButton)

local moveLayerRightButton = Button:new(layerButtonX, layerControlHeight + layerButtonYSpacing * 3, layerButtonWidth, passSelectorBoxHeight, "Move Down")
moveLayerRightButton:action(
    function()
		workingPreset.passes[selectedPass].layers[selectedLayer], workingPreset.passes[selectedPass].layers[selectedLayer - 1] = workingPreset.passes[selectedPass].layers[selectedLayer - 1], workingPreset.passes[selectedPass].layers[selectedLayer]
		selectedLayer = selectedLayer - 1
		refreshWindowLayers()
		updatePresetLayerButtons()
    end)
presetEditorWindow:addComponent(moveLayerRightButton)

local cloneLayerButton = Button:new(layerButtonX, layerControlHeight + layerButtonYSpacing * 4, layerButtonWidth, passSelectorBoxHeight, "Clone")
cloneLayerButton:action(
    function()
		table.insert(workingPreset.passes[selectedPass].layers, selectedLayer + 1, CopyTable(workingPreset.passes[selectedPass].layers[selectedLayer]))
		selectedLayer = selectedLayer + 1
		
		refreshWindowLayers()
		updatePresetLayerButtons()
    end)
presetEditorWindow:addComponent(cloneLayerButton)



local layerEditingX = layerButtonX + layerButtonWidth + 10
local layerEditingY = layerControlHeight
local layerEditingWidth = presetEditorWindowWidth - layerEditingX - 10
local layerEditingX2 = layerEditingX + layerEditingWidth / 2

local layerModeText = "Layer Mode:"
local layerModeLabelSize = graphics.textSize(layerModeText)
local layerModeLabel = Label:new(layerEditingX, layerEditingY, layerEditingWidth / 4, 16, layerModeText)
presetEditorWindow:addComponent(layerModeLabel)

local layerModeDropdown = Button:new(layerEditingX + layerEditingWidth / 4, layerEditingY, layerEditingWidth / 4, 16)
layerModeDropdown:action(
	function(sender)
		-- Does this actually do anything?
		local windowX, windowY = presetEditorWindow:position()
		createDropdown(presetModeNames, layerEditingX + layerEditingWidth / 4 + windowX, layerEditingY + windowY, layerEditingWidth / 4, 16, 
			function(a)
				workingPreset.passes[selectedPass].layers[selectedLayer].mode = a
				resetLayerMode(workingPreset.passes[selectedPass].layers[selectedLayer])
				refreshWindowLayers()
				updatePresetLayerButtons()
			end)
	end)
presetEditorWindow:addComponent(layerModeDropdown)

local layerElementText = "Layer Type:"
local layerElementLabelSize = graphics.textSize(layerElementText)
local layerElementLabel = Label:new(layerEditingX + layerEditingWidth / 2, layerEditingY, layerEditingWidth / 4, 16, layerElementText)
presetEditorWindow:addComponent(layerElementLabel)

local layerElementTextbox = Textbox:new(layerEditingX + layerEditingWidth / 4 * 3, layerEditingY, layerEditingWidth / 4, 16)
layerElementTextbox:onTextChanged(
	function(sender)
		local elemName = sender:text()

		for i=0,2^sim.PMAPBITS-1 do
			local isElem, name = pcall(function() return elem.property(i, "Name") end)
			if isElem and name == string.upper(elemName) then
				workingPreset.passes[selectedPass].layers[selectedLayer].type = i
				return
			end
		end
		workingPreset.passes[selectedPass].layers[selectedLayer].type = elem.DEFAULT_PT_SAND
	end)
presetEditorWindow:addComponent(layerElementTextbox)

local layerPropertyBoxX = layerEditingX + 4
local layerPropertyBoxY = layerEditingY + 22
local layerPropertyBoxWidth = layerEditingWidth - 8
local layerPropertyBoxHeight = 124
local layerPropertyBoxPadding = 8

local layerPropertyBox = Button:new(layerPropertyBoxX, layerPropertyBoxY, layerPropertyBoxWidth, layerPropertyBoxHeight)
layerPropertyBox:enabled(false)
presetEditorWindow:addComponent(layerPropertyBox)

local layerPropertyInputs = {}

local layerPropertyBoxInputWidth = 40
function createLayerPropertyInput(x, y, property, constraints)
	local width = layerPropertyBoxWidth / 2 - layerPropertyBoxPadding * 2
	local height = 18
	local actualX = layerPropertyBoxX + layerPropertyBoxPadding + (width + layerPropertyBoxPadding * 2) * x
	local actualY = layerPropertyBoxY + layerPropertyBoxPadding + height * y

	if constraints.type == "number" then
		local modeNum = workingPreset.passes[selectedPass].layers[selectedLayer].mode
		local inputText = constraints.text
		local inputTextSize = graphics.textSize(inputText)
		local inputTextLabel = Label:new(actualX, actualY, inputTextSize, height, inputText)
		presetEditorWindow:addComponent(inputTextLabel)
		layerPropertyInputs[inputTextLabel] = {}

		local inputBox = Textbox:new(actualX + width - layerPropertyBoxInputWidth, actualY, layerPropertyBoxInputWidth, height, 16)
		inputBox:onTextChanged(
			function(sender)
				local inputConstraints = presetModeFieldConstraints[modeNum][layerPropertyInputs[sender]]
				local newValue = tonumber(sender:text())
				if sender:text() == "" then newValue = 0 end
				if newValue then
					newValue = math.min(math.max(newValue, inputConstraints.min), inputConstraints.max)
					if not inputConstraints.fraction then
						newValue = math.floor(newValue)
					end
					workingPreset.passes[selectedPass].layers[selectedLayer][inputConstraints.prop] = newValue
				else
					sender:text(workingPreset.passes[selectedPass].layers[selectedLayer][inputConstraints.prop])
				end
			end)
		inputBox:text(workingPreset.passes[selectedPass].layers[selectedLayer][presetModeFieldConstraints[modeNum][property].prop])
		presetEditorWindow:addComponent(inputBox)
		layerPropertyInputs[inputBox] = property
	end

	if constraints.type == "element" then
		local modeNum = workingPreset.passes[selectedPass].layers[selectedLayer].mode
		local inputText = constraints.text
		local inputTextSize = graphics.textSize(inputText)
		local inputTextLabel = Label:new(actualX, actualY, inputTextSize, height, inputText)
		presetEditorWindow:addComponent(inputTextLabel)
		layerPropertyInputs[inputTextLabel] = {}

		local inputBox = Textbox:new(actualX + width - layerPropertyBoxInputWidth, actualY, layerPropertyBoxInputWidth, height, 16)
		inputBox:onTextChanged(
			function(sender)
				local inputConstraints = presetModeFieldConstraints[modeNum][layerPropertyInputs[sender]]
				local newValue = sender:text()

				for i=0,2^sim.PMAPBITS-1 do
					local isElem, name = pcall(function() return elem.property(i, "Name") end)
					if isElem and name == string.upper(newValue) then
						workingPreset.passes[selectedPass].layers[selectedLayer][inputConstraints.prop] = i
						return
					end
				end
				workingPreset.passes[selectedPass].layers[selectedLayer][inputConstraints.prop] = elem.DEFAULT_PT_SAND
			end)
		inputBox:text(elem.property(workingPreset.passes[selectedPass].layers[selectedLayer][presetModeFieldConstraints[modeNum][property].prop], "Name"))
		presetEditorWindow:addComponent(inputBox)
		layerPropertyInputs[inputBox] = property
	end	

	if constraints.type == "boolean" then
		local modeNum = workingPreset.passes[selectedPass].layers[selectedLayer].mode
		local inputText = constraints.text
		local inputTextSize = graphics.textSize(inputText)
	
		local inputBox = Checkbox:new(actualX, actualY, width, height, inputText)
		inputBox:action(
			function(sender, checked)
				local inputConstraints = presetModeFieldConstraints[modeNum][layerPropertyInputs[sender]]
				workingPreset.passes[selectedPass].layers[selectedLayer][inputConstraints.prop] = checked
			end)
		inputBox:checked(workingPreset.passes[selectedPass].layers[selectedLayer][presetModeFieldConstraints[modeNum][property].prop])
		presetEditorWindow:addComponent(inputBox)
		layerPropertyInputs[inputBox] = property
	end
end

function refreshLayerPropertyInputs()
	for k,j in pairs(layerPropertyInputs) do
		presetEditorWindow:removeComponent(k)
	end
	layerPropertyInputs = {}
	if selectedLayer then
		local mode = workingPreset.passes[selectedPass].layers[selectedLayer].mode
		local constraints = presetModeFieldConstraints[mode]
		local i = 0
		for k,j in ipairs(constraints) do
			createLayerPropertyInput(i % 2, math.floor(i / 2), k, j)
			i = i + 1
		end
	end
end


local windowLayerSelections = {}
local windowSelectionButtons = {}
function refreshWindowLayers()
	layerPage = 1
	for k,j in pairs(windowLayerSelections) do
		presetEditorWindow:removeComponent(k)
	end
	windowLayerSelections = {}
	windowSelectionButtons = {}
	if workingPreset.passes[selectedPass] then
		for k,j in pairs(workingPreset.passes[selectedPass].layers) do
			local layerButton = Button:new(layerSelectorBoxX, layerControlHeight + layerSelectorBoxHeight - (passSelectorBoxHeight) * ((k - 1) % layersPerPage + 1) - 1, layerSelectorBoxWidth, layerButtonHeight)
			-- layerButton:text(k .. ": " .. elem.property(j.type, "Name") .. " (" .. presetModeShortNames[j.mode] .. ")")
			layerButton:action(
				function()
					selectedLayer = windowLayerSelections[layerButton]
					-- refreshWindowPresets()
					refreshLayerSelectionButtonState()
					updatePresetButtons()
				end)
			windowLayerSelections[layerButton] = k
			windowSelectionButtons[k] = layerButton
		end
		if selectedLayer ~= nil then
			layerPage = math.max(math.ceil(selectedLayer / layersPerPage), 1)
		end
		refreshLayerSelectionButtonState()
	end
	refreshLayerPages()
	-- refreshPresetSelectionText()
end

function refreshLayerPages()
	for k,j in pairs(windowLayerSelections) do
		presetEditorWindow:removeComponent(k)
	end
	if workingPreset.passes[selectedPass] then
		layerPageCount = math.max(math.ceil(#workingPreset.passes[selectedPass].layers / layersPerPage), 1)
	else
		layerPageCount = 1
	end

	if layerPage > layerPageCount then
		layerPage = layerPageCount
	end

	layerPageLabel:text(layerPage .. "/" .. layerPageCount)

	for i=1,layersPerPage do
		local button = windowSelectionButtons[(layerPage - 1) * layersPerPage + i]
		if button then
			presetEditorWindow:addComponent(button)
		end
	end
	updatePresetLayerButtons()
end

function refreshLayerSelectionButtonState()
	for l,m in pairs(windowLayerSelections) do
		local layer = workingPreset.passes[selectedPass].layers[m]
		l:enabled(m ~= selectedLayer) 
		l:text(m .. ": " .. elem.property(layer.type, "Name") .. " (" .. presetModeShortNames[layer.mode] .. ")")
	end
end





local saveButton = Button:new(presetEditorWindowWidth-220, presetEditorWindowHeight-26, 100, 16, "Save & Close")
saveButton:action(
    function()
		loadedPresets[selectedFolder][selectedPreset] = json.stringify(workingPreset)
		workingPreset = nil
		saveChanges()
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
	-- Passes
	addPassButton:enabled(#workingPreset.passes < MaxPasses)
	deletePassButton:enabled(selectedPass ~= nil)
	movePassLeftButton:enabled(selectedPass ~= nil and selectedPass > 1)
	movePassRightButton:enabled(selectedPass ~= nil and selectedPass < #workingPreset.passes)
	clonePassButton:enabled(selectedPass ~= nil and #workingPreset.passes < MaxPasses)

	-- Pass editing
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

	-- Layer selection
	updatePresetLayerButtons()
end

function updatePresetLayerButtons()
	if selectedLayer then
		addLayerButton:enabled(#workingPreset.passes[selectedPass].layers < MaxPasses)
		deleteLayerButton:enabled(true)
		moveLayerLeftButton:enabled(selectedLayer < #workingPreset.passes[selectedPass].layers)
		moveLayerRightButton:enabled(selectedLayer > 1)
		cloneLayerButton:enabled(#workingPreset.passes[selectedPass].layers < MaxPasses)

		layerModeDropdown:enabled(true)
		layerModeDropdown:text(presetModeNames[workingPreset.passes[selectedPass].layers[selectedLayer].mode])

		layerElementTextbox:readonly(false)
		layerElementTextbox:text(elem.property(workingPreset.passes[selectedPass].layers[selectedLayer].type, "Name"))
	else
		addLayerButton:enabled(selectedPass ~= nil)
		deleteLayerButton:enabled(false)
		moveLayerLeftButton:enabled(false)
		moveLayerRightButton:enabled(false)
		cloneLayerButton:enabled(false)

		layerModeDropdown:enabled(false)
		layerModeDropdown:text("...")
		
		layerElementTextbox:readonly(true)
		layerElementTextbox:text("Name...")
	end
	updatePresetLayerPageButtons()
	refreshLayerPropertyInputs()
end

function updatePresetLayerPageButtons()
	layerPageLeft:enabled(layerPage > 1)
	layerPageRight:enabled(layerPage < layerPageCount)
end


function setupEditorWindow()
	workingPreset = json.parse(loadedPresets[selectedFolder][selectedPreset])
	selectedPass = nil
	selectedLayer = nil

	refreshWindowPasses()
	updatePresetButtons()
end



local flashTimer = 0
local terraGenStaticMessage = "Territect is running..."
local terraGenStatus = "Idle"

event.register(event.tick, function()
    if terraGenRunning then
		local brightness = 180 - math.sin(flashTimer * math.pi / 15) * 20
		local w, h = graphics.textSize(terraGenStaticMessage)
		graphics.drawText(sim.XRES / 2 - w / 2, 25, terraGenStaticMessage, brightness, brightness, brightness)
		local text = terraGenStatus
		if tpt.set_pause() == 1 then
			text = "Paused"
		end
		local w, h = graphics.textSize(text)
		graphics.drawText(sim.XRES / 2 - w / 2, 40, text, brightness, brightness, brightness)
		flashTimer = (flashTimer + 1) % 30

		if tpt.set_pause() == 0 then
			coroutine.resume(terraGenCoroutine)
		end
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
			for l=1,amt do
				xH[i] = xH[i] + 1
				vtk[i][xH[i]] = j.type 
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
			for l=1,amt do
				xH[i] = xH[i] + 1
				vtk[i][xH[i]] = j.type 
			end
		end
		return j, xH, vtk
	end,
	[3] = function(j, xH, vtk)
		for v=1,j.veinCount do
			local x = math.random(sim.XRES)
			local y = math.random(j.minY, j.maxY) + 1
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
	end,
	[4] = function(j, xH, vtk)
		if j.inExisting then
			for k in sim.parts() do
				if sim.partProperty(k, "type") == j.oldType and math.random() <= j.percent / 100 then
					if j.preserveProps then
						sim.partChangeType(k, j.type)
					else
						local x, y = sim.partPosition(k)
						x, y = math.floor(x + 0.5), math.floor(y + 0.5)
						sim.partKill(k)
						sim.partCreate(-3, x, y, j.type)
					end
				end
			end
		end
		if j.inLayer then
			for h,k in pairs(vtk) do
				for l,m in pairs(k) do
					if m == j.oldType and math.random() <= j.percent / 100 then vtk[h][l] = j.type end 
				end
			end
		end

		return j, xH, vtk
	end
}



local originalProperties = {}
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
	
		resetElementProperties()
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

		-- Reset twice to ensure modified element properties are still reset if TerraGen is interrupted by itself.
		resetElementProperties()
	end

	terraGenRunning = false
	coroutine.yield()
end


function resetElementProperties()
	for k,j in pairs(originalProperties) do
		for l,m in pairs(j) do
			elem.property(k, l, m)
		end
	end
	originalProperties = {}
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