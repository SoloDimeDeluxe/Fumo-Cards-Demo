local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("GameplayRemotes")
local setSprintingEvent = remotes:WaitForChild("SetSprinting")

local SPRINT_KEY = Enum.KeyCode.LeftShift
local SPRINT_ACTION = "Sprint"
local NORMAL_COLOR = Color3.fromRGB(240, 220, 120)
local EXHAUSTED_COLOR = Color3.fromRGB(120, 120, 120)
local BACKGROUND_COLOR = Color3.fromRGB(30, 30, 30)
local HEALTH_DRAIN_COLOR = Color3.fromRGB(220, 40, 40)

---------------------------------------------------------------------
-- Input: only tells the server what we want, the server validates it
---------------------------------------------------------------------

local function handleSprint(_actionName, inputState)
	if inputState == Enum.UserInputState.Begin then
		setSprintingEvent:FireServer(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		-- Cancel covers things like the finger sliding off the button
		setSprintingEvent:FireServer(false)
	end
	return Enum.ContextActionResult.Sink
end

-- true = also create an on-screen button on touch devices
-- Shift on keyboard, left stick click on gamepad
ContextActionService:BindAction(SPRINT_ACTION, handleSprint, true, SPRINT_KEY, Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle(SPRINT_ACTION, "Correr")

---------------------------------------------------------------------
-- Stamina bar (bottom center)
---------------------------------------------------------------------

local staminaGui = Instance.new("ScreenGui")
staminaGui.Name = "StaminaGui"
staminaGui.ResetOnSpawn = false
staminaGui.Parent = player:WaitForChild("PlayerGui")

local barBackground = Instance.new("Frame")
barBackground.AnchorPoint = Vector2.new(0.5, 1)
barBackground.Position = UDim2.new(0.5, 0, 1, -30)
barBackground.Size = UDim2.fromOffset(300, 14)
barBackground.BackgroundColor3 = BACKGROUND_COLOR
barBackground.BorderSizePixel = 0
barBackground.Parent = staminaGui
Instance.new("UICorner", barBackground).CornerRadius = UDim.new(1, 0)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(1, 1)
barFill.BackgroundColor3 = NORMAL_COLOR
barFill.BorderSizePixel = 0
barFill.Parent = barBackground
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

RunService.RenderStepped:Connect(function()
	local stamina = player:GetAttribute("Stamina") or 0
	local maxStamina = player:GetAttribute("MaxStamina") or 100
	local isExhausted = player:GetAttribute("Exhausted") == true
	local isSprinting = player:GetAttribute("IsSprinting") == true

	barFill.Size = UDim2.fromScale(stamina / maxStamina, 1)
	barFill.BackgroundColor3 = if isExhausted then EXHAUSTED_COLOR else NORMAL_COLOR

	if isSprinting and stamina <= 0 then
		-- Pulsing red: you're sprinting with no stamina, it's eating your HP
		local pulse = (math.sin(os.clock() * 10) + 1) / 2
		barBackground.BackgroundColor3 = HEALTH_DRAIN_COLOR:Lerp(BACKGROUND_COLOR, pulse * 0.6)
	else
		barBackground.BackgroundColor3 = BACKGROUND_COLOR
	end
end)
