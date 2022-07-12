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










-- Test Window
local terraGenWindow = Window:new(-1, -1, 300, 200)

local currentY = 10

--Example label
local testLabel = Label:new(10, currentY, (select(1, terraGenWindow:size())/2)-20, 16, "Warning: The current simulation will be cleared!")

--Example button
local buttonPresses = 1
currentY = currentY + 20
local testButton = Button:new(10, currentY, (select(1, terraGenWindow:size())/2)-20, 16, "This is a test button")
testButton:enabled(false)
testButton:action(
	function(sender)
		sender:text("Pressed " .. buttonPresses .. " times")
		buttonPresses = buttonPresses + 1
	end
)

--Example Textbox
currentY = currentY + 20
local textboxInfo = Label:new(10+((select(1, terraGenWindow:size())/2)-20), currentY, (select(1, terraGenWindow:size())/2)-20, 16, "0 characters")
local testTextbox = Textbox:new(10, currentY, (select(1, terraGenWindow:size())/2)-20, 16, "", "[place text here]")
testTextbox:onTextChanged(
	function(sender)
		textboxInfo:text(sender:text():len().." characters");
	end
)

--Example Checkbox
currentY = currentY + 20
local testCheckbox = Checkbox:new(10, currentY, (select(1, terraGenWindow:size())/2)-20, 16, "Unchecked");
testCheckbox:action(
	function(sender, checked)
		if(checked) then
			sender:text("Checked")
		else
			sender:text("Unchecked")
		end
		testButton:enabled(checked);
	end
)

--Example progress bar
currentY = currentY + 20
local testProgressBar = ProgressBar:new(10, currentY, (select(1, terraGenWindow:size())/2)-20, 16, 0, "Slider: 0");

--Example slider
currentY = currentY + 20
local testSlider = Slider:new(10, currentY, (select(1, terraGenWindow:size())/2)-20, 16, 10);
testSlider:onValueChanged(
	function(sender, value)
		testProgressBar:progress(value * 10)
		testProgressBar:status("Slider: " .. value)
	end
)

-- Close button
local closeButton = Button:new(10, select(2, terraGenWindow:size())-26, 100, 16, "Go!")

closeButton:action(
    function()
        interface.closeWindow(terraGenWindow)
        sim.clearSim()
        tpt.set_pause(0)
		terraGenCoroutine = coroutine.create(runTerraGen)
		coroutine.resume(terraGenCoroutine)
		terraGenRunning = true
    end
)

event.register(event.tick, function()
    if terraGenRunning then
		coroutine.resume(terraGenCoroutine)
	end
end)

-- Mode list explanation:
-- 1: Uniform layer
-- 2: Uniform layer w/ padding
-- 3: Veins


local terraGenParams = {
	bottom = 40,
	layers = {
		{ type = elem.DEFAULT_PT_STNE, thickness = 10, variation = 5, mode = 1 },
		{ type = elem.DEFAULT_PT_BGLA, thickness = 10, variation = 5, mode = 1 },
		{ type = elem.DEFAULT_PT_BRMT, thickness = 10, variation = 5, mode = 1 },
		{ type = elem.DEFAULT_PT_PQRT, veinCount = 3, minY = 0, maxY = 30, width = 120, height = 5, mode = 3 },
		{ type = elem.DEFAULT_PT_STNE, thickness = 10, variation = 5, mode = 1 },
		-- { type = elem.DEFAULT_PT_BCOL, thickness = 1, variation = 2, mode = 3 },
		{ type = elem.DEFAULT_PT_SAND, thickness = 10, variation = 5, mode = 2 }
	}
}



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
		for v=0,j.veinCount do
			local x = math.random(sim.XRES)
			local y = math.random(j.minY, j.maxY)
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
	end




}




function runTerraGen()

	local vtk = {}
	local xH = {}
	for i=0,sim.XRES do
		xH[i] = 0
		vtk[i] = {}
	end

	for k,j in pairs(terraGenParams.layers) do
		j, xH, vtk = terraGenFunctions[j.mode](j, xH, vtk)
		-- for i=0,sim.XRES do
		-- 	local amt = j.thickness + (math.random() - 0.5) * j.variation
		-- 	for l=0,amt do
		-- 		vtk[i][xH[i]] = j.type 
		-- 		xH[i] = xH[i] + 1
		-- 	end
		-- end
	end
		

	for i=0,sim.XRES do
		for k,j in pairs(vtk[i]) do
			sim.partCreate(-1, i, sim.YRES - terraGenParams.bottom - k, j)
		end
		if i % 10 == 0 then
			-- coroutine.yield()
		end
	end

	terraGenRunning = false
end



terraGenWindow:addComponent(testLabel)
terraGenWindow:addComponent(testButton)
terraGenWindow:addComponent(testTextbox)
terraGenWindow:addComponent(testCheckbox)
terraGenWindow:addComponent(testProgressBar)
terraGenWindow:addComponent(testSlider)
terraGenWindow:addComponent(textboxInfo)
terraGenWindow:addComponent(closeButton)


function terraGen()
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