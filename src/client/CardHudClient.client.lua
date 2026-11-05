local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local remotes = ReplicatedStorage:WaitForChild("GameplayRemotes")
local loadoutChangedEvent = remotes:WaitForChild("LoadoutChanged")
local getLoadoutFunction = remotes:WaitForChild("GetLoadout")
local activeCardUsedEvent = remotes:WaitForChild("ActiveCardUsed")

local SLOT_SIZE = UDim2.fromOffset(60, 76)
local HUD_MARGIN = 20
local SLOT_SPACING = 8
local SLOT_BACKGROUND = Color3.fromRGB(20, 20, 20)
local READY_TINT = Color3.new(1, 1, 1)
local COOLDOWN_TINT = Color3.fromRGB(80, 80, 80) -- darkened while the active card recharges
local ACTIVE_KEY_TEXT = "E"

local hudGui = Instance.new("ScreenGui")
hudGui.Name = "CardHudGui"
hudGui.ResetOnSpawn = false
hudGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Row of cards in the bottom left corner
local hudFrame = Instance.new("Frame")
hudFrame.BackgroundTransparency = 1
hudFrame.AnchorPoint = Vector2.new(0, 1)
hudFrame.Position = UDim2.new(0, HUD_MARGIN, 1, -HUD_MARGIN)
hudFrame.Size = UDim2.fromOffset(0, SLOT_SIZE.Y.Offset)
hudFrame.AutomaticSize = Enum.AutomaticSize.X
hudFrame.Parent = hudGui

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, SLOT_SPACING)
listLayout.Parent = hudFrame

-- Card name shown when hovering a slot
local tooltip = Instance.new("TextLabel")
tooltip.AnchorPoint = Vector2.new(0, 1)
tooltip.AutomaticSize = Enum.AutomaticSize.X
tooltip.Size = UDim2.fromOffset(0, 24)
tooltip.BackgroundColor3 = SLOT_BACKGROUND
tooltip.BackgroundTransparency = 0.1
tooltip.TextColor3 = Color3.new(1, 1, 1)
tooltip.Font = Enum.Font.GothamMedium
tooltip.TextSize = 14
tooltip.Visible = false
tooltip.ZIndex = 5
tooltip.Parent = hudGui
Instance.new("UICorner", tooltip).CornerRadius = UDim.new(0, 6)

local tooltipPadding = Instance.new("UIPadding")
tooltipPadding.PaddingLeft = UDim.new(0, 8)
tooltipPadding.PaddingRight = UDim.new(0, 8)
tooltipPadding.Parent = tooltip

local activeSlot = nil   -- the active card's slot, so we can tint it during cooldown
local activeReadyTime = 0

local function createSlot(cardInfo, layoutOrder)
	local slot = Instance.new("ImageLabel")
	slot.Image = cardInfo.ImageId or ""
	slot.Size = SLOT_SIZE
	slot.BackgroundColor3 = SLOT_BACKGROUND
	slot.BackgroundTransparency = 0.3
	slot.ScaleType = Enum.ScaleType.Fit
	slot.LayoutOrder = layoutOrder
	slot.Parent = hudFrame
	Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 6)

	slot.MouseEnter:Connect(function()
		tooltip.Text = cardInfo.DisplayName
		tooltip.Position = UDim2.fromOffset(slot.AbsolutePosition.X, slot.AbsolutePosition.Y - 6)
		tooltip.Visible = true
	end)
	slot.MouseLeave:Connect(function()
		tooltip.Visible = false
	end)

	return slot
end

-- Small key badge in the corner of the active card ("E")
local function addKeyBadge(slot, keyText)
	local badge = Instance.new("TextLabel")
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -3, 0, 3)
	badge.Size = UDim2.fromOffset(20, 20)
	badge.BackgroundColor3 = SLOT_BACKGROUND
	badge.Text = keyText
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 14
	badge.ZIndex = 2
	badge.Parent = slot
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
end

local function addSeparator(layoutOrder)
	local separator = Instance.new("Frame")
	separator.Size = UDim2.fromOffset(2, SLOT_SIZE.Y.Offset - 16)
	separator.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	separator.BorderSizePixel = 0
	separator.LayoutOrder = layoutOrder
	separator.Parent = hudFrame
end

-- Rebuilds the whole row every time the loadout changes (it's tiny, so this is cheap)
local function rebuildHud(loadout)
	for _, child in hudFrame:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	tooltip.Visible = false
	activeSlot = nil

	if not loadout then return end

	local layoutOrder = 0

	if loadout.Active then
		activeSlot = createSlot(loadout.Active, layoutOrder)
		addKeyBadge(activeSlot, ACTIVE_KEY_TEXT)
		activeReadyTime = os.clock() + (loadout.Active.CooldownRemaining or 0)
		layoutOrder += 1

		if #loadout.Passives > 0 then
			addSeparator(layoutOrder)
			layoutOrder += 1
		end
	end

	for _, passiveInfo in loadout.Passives do
		createSlot(passiveInfo, layoutOrder)
		layoutOrder += 1
	end
end

-- When the active card is used, remember when it'll be ready again
activeCardUsedEvent.OnClientEvent:Connect(function(_imageId, cooldown)
	activeReadyTime = os.clock() + cooldown
end)

RunService.RenderStepped:Connect(function()
	if activeSlot then
		activeSlot.ImageColor3 = if os.clock() < activeReadyTime then COOLDOWN_TINT else READY_TINT
	end
end)

loadoutChangedEvent.OnClientEvent:Connect(rebuildHud)
rebuildHud(getLoadoutFunction:InvokeServer())
