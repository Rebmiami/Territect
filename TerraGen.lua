print("Thank you for downloading TerraGen! To activate, please type 'TerraGen()' in the console (~) and press enter.")


-- Test Window
local terraGenWindow = Window:new(-1, -1, 300, 200)

local currentY = 10

--Example label
local testLabel = Label:new(10, currentY, (select(1, terraGenWindow:size())/2)-20, 16, "This is a test label")

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
local closeButton = Button:new(10, select(2, terraGenWindow:size())-26, 100, 16, "Close")

closeButton:action(function() interface.closeWindow(terraGenWindow) end)

terraGenWindow:onTryExit(function() interface.closeWindow(terraGenWindow) end) -- Allow the default exit events
terraGenWindow:onMouseMove(
	function(x, y, dx, dy)
		testLabel:text("Mouse: "..x..", "..y)
	end
)

terraGenWindow:addComponent(testLabel)
terraGenWindow:addComponent(testButton)
terraGenWindow:addComponent(testTextbox)
terraGenWindow:addComponent(testCheckbox)
terraGenWindow:addComponent(testProgressBar)
terraGenWindow:addComponent(testSlider)
terraGenWindow:addComponent(textboxInfo)
terraGenWindow:addComponent(closeButton)

function TerraGen()
    interface.showWindow(terraGenWindow)
end
