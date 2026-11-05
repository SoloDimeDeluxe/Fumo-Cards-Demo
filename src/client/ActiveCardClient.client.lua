local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local ContextActionService = game:GetService("ContextActionService")

local remotes = ReplicatedStorage:WaitForChild("GameplayRemotes")
local useActiveCardEvent = remotes:WaitForChild("UseActiveCard")
local activeCardUsedEvent = remotes:WaitForChild("ActiveCardUsed")

local ACTIVE_CARD_KEY = Enum.KeyCode.E
local ACTIVE_CARD_ACTION = "UseActiveCard"
local CARD_SIZE = UDim2.fromOffset(190, 240)
local COOLDOWN_ICON_SIZE = UDim2.fromOffset(80, 101)
local COOLDOWN_ICON_MARGIN = 20
local TOP_BAR_OFFSET = 60

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local cardGui = Instance.new("ScreenGui")
cardGui.Name = "ActiveCardGui"
cardGui.ResetOnSpawn = false
cardGui.IgnoreGuiInset = true
cardGui.Parent = playerGui

---------------------------------------------------------------------
-- Cooldown icon (top right)
---------------------------------------------------------------------

local cooldownIcon = Instance.new("ImageLabel")
cooldownIcon.Name = "CooldownIcon"
cooldownIcon.BackgroundTransparency = 1
cooldownIcon.AnchorPoint = Vector2.new(1, 0)
cooldownIcon.Position = UDim2.new(1, -COOLDOWN_ICON_MARGIN, 0, TOP_BAR_OFFSET)
cooldownIcon.Size = COOLDOWN_ICON_SIZE
cooldownIcon.Visible = false
cooldownIcon.ClipsDescendants = true
cooldownIcon.Parent = cardGui

local iconScale = Instance.new("UIScale")
iconScale.Parent = cooldownIcon

-- Dark layer anchored at the bottom: it shrinks as the cooldown runs out
local cooldownOverlay = Instance.new("Frame")
cooldownOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
cooldownOverlay.BackgroundTransparency = 0.35
cooldownOverlay.BorderSizePixel = 0
cooldownOverlay.AnchorPoint = Vector2.new(0, 1)
cooldownOverlay.Position = UDim2.fromScale(0, 1)
cooldownOverlay.Size = UDim2.fromScale(1, 1)
cooldownOverlay.Parent = cooldownIcon

-- Seconds left, drawn on top of everything
local countdownLabel = Instance.new("TextLabel")
countdownLabel.BackgroundTransparency = 1
countdownLabel.Size = UDim2.fromScale(1, 1)
countdownLabel.Font = Enum.Font.GothamBold
countdownLabel.TextColor3 = Color3.new(1, 1, 1)
countdownLabel.TextScaled = true
countdownLabel.ZIndex = 2
countdownLabel.Parent = cooldownIcon

local countdownStroke = Instance.new("UIStroke")
countdownStroke.Thickness = 2
countdownStroke.Parent = countdownLabel

local countdownPadding = Instance.new("UIPadding")
countdownPadding.PaddingTop = UDim.new(0.3, 0)
countdownPadding.PaddingBottom = UDim.new(0.3, 0)
countdownPadding.Parent = countdownLabel

local cooldownConnection = nil

local function finishCooldown()
	if cooldownConnection then
		cooldownConnection:Disconnect()
		cooldownConnection = nil
	end

	-- Small "ready" pop, then hide the icon
	cooldownOverlay.Size = UDim2.fromScale(1, 0)
	countdownLabel.Text = ""
	local popInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
	local popTween = TweenService:Create(iconScale, popInfo, { Scale = 1.2 })
	popTween:Play()
	popTween.Completed:Wait()
	cooldownIcon.Visible = false
end

local function startCooldownDisplay(imageId, cooldownDuration)
	if cooldownDuration <= 0 then return end

	-- If a previous countdown was running, replace it
	if cooldownConnection then
		cooldownConnection:Disconnect()
	end

	local endTime = os.clock() + cooldownDuration
	cooldownIcon.Image = imageId
	iconScale.Scale = 1
	cooldownIcon.Visible = true

	-- Runs every frame until the cooldown is over
	cooldownConnection = RunService.RenderStepped:Connect(function()
		local timeLeft = endTime - os.clock()
		if timeLeft <= 0 then
			task.spawn(finishCooldown)
			return
		end

		cooldownOverlay.Size = UDim2.fromScale(1, timeLeft / cooldownDuration)
		countdownLabel.Text = tostring(math.ceil(timeLeft))
	end)
end

---------------------------------------------------------------------
-- Card cast animation (center of the screen)
---------------------------------------------------------------------

local function playCardCastAnimation(imageId)
	local cardImage = Instance.new("ImageLabel")
	cardImage.Image = imageId
	cardImage.BackgroundTransparency = 1
	cardImage.AnchorPoint = Vector2.new(0.5, 0.5)
	cardImage.Position = UDim2.fromScale(0.5, 0.8)
	cardImage.Size = CARD_SIZE
	cardImage.Rotation = -20
	cardImage.ImageTransparency = 1
	cardImage.Parent = cardGui

	-- UIScale lets us grow/shrink the card without touching its Size
	local cardScale = Instance.new("UIScale")
	cardScale.Scale = 0
	cardScale.Parent = cardImage

	-- 1) Pop in: grows with a little overshoot, straightens up and becomes visible
	local popInInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(cardScale, popInInfo, { Scale = 1 }):Play()
	local popInTween = TweenService:Create(cardImage, popInInfo, {
		Rotation = 0,
		ImageTransparency = 0,
		Position = UDim2.fromScale(0.5, 0.65),
	})
	popInTween:Play()
	popInTween.Completed:Wait()

	-- 2) Hold so the player can see which card was used
	task.wait(0.5)

	-- 3) Fly up while growing slightly and fading out
	local fadeOutInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(cardScale, fadeOutInfo, { Scale = 1.2 }):Play()
	local fadeOutTween = TweenService:Create(cardImage, fadeOutInfo, {
		ImageTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.45),
	})
	fadeOutTween:Play()
	fadeOutTween.Completed:Wait()

	cardImage:Destroy()
end

---------------------------------------------------------------------
-- Client effects any card can request
---------------------------------------------------------------------

-- Solid white silhouette visible through walls, only for this player
local function addSilhouette(target, duration)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = target
	highlight.Parent = target
	Debris:AddItem(highlight, duration)
end

local function playClientEffects(clientEffects)
	local silhouettes = clientEffects.Silhouettes
	if silhouettes then
		for _, target in silhouettes.Targets do
			addSilhouette(target, silhouettes.Duration)
		end
	end
	-- Future cards can add new effect types here (screen tint, sounds, etc.)
end

---------------------------------------------------------------------
-- Input and server response
---------------------------------------------------------------------

local function handleActiveCard(_actionName, inputState)
	if inputState == Enum.UserInputState.Begin then
		useActiveCardEvent:FireServer()
	end
	return Enum.ContextActionResult.Sink
end

-- E on keyboard, X on gamepad, and an on-screen button on touch devices
ContextActionService:BindAction(ACTIVE_CARD_ACTION, handleActiveCard, true, ACTIVE_CARD_KEY, Enum.KeyCode.ButtonX)
ContextActionService:SetTitle(ACTIVE_CARD_ACTION, "Carta")

activeCardUsedEvent.OnClientEvent:Connect(function(imageId, cooldown, clientEffects)
	-- task.spawn so the animation's waits don't delay the actual effect
	task.spawn(playCardCastAnimation, imageId)
	startCooldownDisplay(imageId, cooldown)
	playClientEffects(clientEffects)
end)
