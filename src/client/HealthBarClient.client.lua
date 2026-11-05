local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

local BAR_SIZE = UDim2.fromOffset(300, 18)
local BAR_POSITION = UDim2.new(0.5, 0, 1, -50) -- just above the stamina bar
local BACKGROUND_COLOR = Color3.fromRGB(30, 30, 30)
local HEALTHY_COLOR = Color3.fromRGB(90, 200, 90)
local LOW_HEALTH_COLOR = Color3.fromRGB(220, 50, 50)
local DAMAGE_TRAIL_COLOR = Color3.fromRGB(255, 255, 255)
local DAMAGE_TRAIL_SPEED = 3 -- how fast the white "recent damage" part catches up

-- Our bar replaces Roblox's default health bar (top right)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)

local healthGui = Instance.new("ScreenGui")
healthGui.Name = "HealthGui"
healthGui.ResetOnSpawn = false
healthGui.Parent = player:WaitForChild("PlayerGui")

local barBackground = Instance.new("Frame")
barBackground.AnchorPoint = Vector2.new(0.5, 1)
barBackground.Position = BAR_POSITION
barBackground.Size = BAR_SIZE
barBackground.BackgroundColor3 = BACKGROUND_COLOR
barBackground.BorderSizePixel = 0
barBackground.ClipsDescendants = true
barBackground.Parent = healthGui
Instance.new("UICorner", barBackground).CornerRadius = UDim.new(1, 0)

-- White bar behind the real one: shows the HP you just lost, then shrinks
local damageTrail = Instance.new("Frame")
damageTrail.Size = UDim2.fromScale(1, 1)
damageTrail.BackgroundColor3 = DAMAGE_TRAIL_COLOR
damageTrail.BorderSizePixel = 0
damageTrail.Parent = barBackground
Instance.new("UICorner", damageTrail).CornerRadius = UDim.new(1, 0)

local healthFill = Instance.new("Frame")
healthFill.Size = UDim2.fromScale(1, 1)
healthFill.BackgroundColor3 = HEALTHY_COLOR
healthFill.BorderSizePixel = 0
healthFill.Parent = barBackground
Instance.new("UICorner", healthFill).CornerRadius = UDim.new(1, 0)

-- "175 / 175" on top of the bar
local healthText = Instance.new("TextLabel")
healthText.BackgroundTransparency = 1
healthText.Size = UDim2.fromScale(1, 1)
healthText.Font = Enum.Font.GothamBold
healthText.TextScaled = true
healthText.TextColor3 = Color3.new(1, 1, 1)
healthText.ZIndex = 2
healthText.Parent = barBackground

local textStroke = Instance.new("UIStroke")
textStroke.Thickness = 1.5
textStroke.Parent = healthText

local textPadding = Instance.new("UIPadding")
textPadding.PaddingTop = UDim.new(0.1, 0)
textPadding.PaddingBottom = UDim.new(0.1, 0)
textPadding.Parent = healthText

local trailFraction = 1

RunService.RenderStepped:Connect(function(deltaTime)
	-- Read the current character every frame so it keeps working after respawning
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local healthFraction = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)

	healthFill.Size = UDim2.fromScale(healthFraction, 1)
	-- Green when healthy, gradually red as it drops
	healthFill.BackgroundColor3 = LOW_HEALTH_COLOR:Lerp(HEALTHY_COLOR, healthFraction)

	-- When healing, the trail jumps with you; when hurt, it slides down slowly
	if healthFraction >= trailFraction then
		trailFraction = healthFraction
	else
		trailFraction = math.max(
			trailFraction - DAMAGE_TRAIL_SPEED * deltaTime * (trailFraction - healthFraction + 0.05),
			healthFraction
		)
	end
	damageTrail.Size = UDim2.fromScale(trailFraction, 1)

	healthText.Text = string.format("%d / %d", math.ceil(humanoid.Health), humanoid.MaxHealth)
end)
