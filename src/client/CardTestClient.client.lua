local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("GameplayRemotes")
local toggleCardEvent = remotes:WaitForChild("ToggleCard")

-- Test keys to turn each card on/off and compare (only works while CardService TEST_MODE is on)
local TEST_KEYBINDS = {
	[Enum.KeyCode.One] = "PhysicalEnhancementJizo",
	[Enum.KeyCode.Two] = "SurvivalOfTheFittest",
	[Enum.KeyCode.Three] = "SpiritPowerSampleBottle",
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	local cardId = TEST_KEYBINDS[input.KeyCode]
	if cardId then
		toggleCardEvent:FireServer(cardId)
	end
end)
