local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CARDS_FOLDER = script.Parent:WaitForChild("Cards")
local BASE_MAX_HEALTH = 100

-- Test setup: cards every player starts with, and keys to toggle them
local TEST_MODE = true
local TEST_LOADOUT = { "PhysicalEnhancementJizo", "SurvivalOfTheFittest", "SpiritPowerSampleBottle" }

-- How each passive modifier combines when several equipped cards provide it
local MODIFIER_RULES = {
	MaxHealthBonus = "Highest",       -- wiki: health cards don't stack, best one wins
	StillRegenMultiplier = "Highest",
	CanSprintWhenExhausted = "Any",   -- true if at least one card gives it
}

-- Value of each modifier when no card provides it
local MODIFIER_DEFAULTS = {
	MaxHealthBonus = 0,
	StillRegenMultiplier = 1,
	CanSprintWhenExhausted = false,
}

-- Load every card module once: cardDefinitions["PhysicalEnhancementJizo"] = { ... }
local cardDefinitions = {}
for _, cardModule in CARDS_FOLDER:GetChildren() do
	if not cardModule:IsA("ModuleScript") then continue end

	local card = require(cardModule)
	if card.Type == "Active" and typeof(card.Activate) ~= "function" then
		warn("Active card has no Activate function:", cardModule.Name)
		continue
	end
	cardDefinitions[cardModule.Name] = card
end

-- Get-or-create, so several scripts can share the same remotes folder safely
local function getOrCreate(parent, className, name)
	local instance = parent:FindFirstChild(name)
	if not instance then
		instance = Instance.new(className)
		instance.Name = name
		instance.Parent = parent
	end
	return instance
end

local remotesFolder = getOrCreate(ReplicatedStorage, "Folder", "GameplayRemotes")
local toggleCardEvent = getOrCreate(remotesFolder, "RemoteEvent", "ToggleCard")
local useActiveCardEvent = getOrCreate(remotesFolder, "RemoteEvent", "UseActiveCard")
local activeCardUsedEvent = getOrCreate(remotesFolder, "RemoteEvent", "ActiveCardUsed")
local loadoutChangedEvent = getOrCreate(remotesFolder, "RemoteEvent", "LoadoutChanged")
local getLoadoutFunction = getOrCreate(remotesFolder, "RemoteFunction", "GetLoadout")

local equippedPassivesByPlayer = {} -- [player] = { [cardId] = true }
local activeCardByPlayer = {}       -- [player] = cardId (only one active card at a time)
local activeReadyTimeByPlayer = {}  -- [player] = os.clock() time when it can be used again

---------------------------------------------------------------------
-- Passive cards
---------------------------------------------------------------------

local function combineModifiers(equippedPassives)
	local result = table.clone(MODIFIER_DEFAULTS)

	for cardId in equippedPassives do
		local card = cardDefinitions[cardId]
		if not card or not card.Modifiers then continue end

		for modifierName, value in card.Modifiers do
			local rule = MODIFIER_RULES[modifierName]
			if rule == "Highest" then
				result[modifierName] = math.max(result[modifierName], value)
			elseif rule == "Any" then
				result[modifierName] = result[modifierName] or value
			else
				warn("Unknown modifier", modifierName, "in card", cardId)
			end
		end
	end

	return result
end

local function applyModifiers(player, isNewCharacter)
	local modifiers = combineModifiers(equippedPassivesByPlayer[player] or {})

	-- Published as player attributes so StatsService and the UI can read them
	for modifierName, value in modifiers do
		player:SetAttribute(modifierName, value)
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local newMaxHealth = BASE_MAX_HEALTH + modifiers.MaxHealthBonus
	local healthDifference = newMaxHealth - humanoid.MaxHealth
	humanoid.MaxHealth = newMaxHealth -- Roblox clamps Health automatically if it went down

	if isNewCharacter then
		humanoid.Health = newMaxHealth
	elseif healthDifference > 0 and humanoid.Health > 0 then
		-- Gaining max HP mid-round also gives you that extra HP
		humanoid.Health += healthDifference
	end
end

---------------------------------------------------------------------
-- Loadout info for the client HUD (the client can't read the card modules)
---------------------------------------------------------------------

local function getCardInfo(cardId)
	local card = cardDefinitions[cardId]
	return {
		Id = cardId,
		DisplayName = card.DisplayName,
		ImageId = card.ImageId,
	}
end

local function buildLoadout(player)
	local passives = {}
	for cardId in equippedPassivesByPlayer[player] or {} do
		table.insert(passives, getCardInfo(cardId))
	end
	-- Sorted so the HUD order doesn't jump around when toggling cards
	table.sort(passives, function(cardA, cardB)
		return cardA.DisplayName < cardB.DisplayName
	end)

	local active = nil
	local activeCardId = activeCardByPlayer[player]
	if activeCardId then
		active = getCardInfo(activeCardId)
		active.CooldownRemaining = math.max((activeReadyTimeByPlayer[player] or 0) - os.clock(), 0)
	end

	return { Active = active, Passives = passives }
end

local function sendLoadout(player)
	loadoutChangedEvent:FireClient(player, buildLoadout(player))
end

-- The client asks for its loadout once when its HUD script starts
getLoadoutFunction.OnServerInvoke = function(player)
	if not equippedPassivesByPlayer[player] then
		return { Active = nil, Passives = {} }
	end
	return buildLoadout(player)
end

---------------------------------------------------------------------
-- Equipping (works the same for passive and active cards)
---------------------------------------------------------------------

local function isEquipped(player, cardId)
	if cardDefinitions[cardId].Type == "Active" then
		return activeCardByPlayer[player] == cardId
	end
	return equippedPassivesByPlayer[player][cardId] == true
end

local function equipCard(player, cardId)
	local card = cardDefinitions[cardId]
	if not card then
		warn("Card does not exist:", cardId)
		return
	end

	if card.Type == "Active" then
		-- Equipping a new active card replaces the previous one
		activeCardByPlayer[player] = cardId
		activeReadyTimeByPlayer[player] = 0
	else
		equippedPassivesByPlayer[player][cardId] = true
		applyModifiers(player, false)
	end

	sendLoadout(player)
end

local function unequipCard(player, cardId)
	local card = cardDefinitions[cardId]
	if not card then return end

	if card.Type == "Active" then
		if activeCardByPlayer[player] == cardId then
			activeCardByPlayer[player] = nil
		end
	else
		equippedPassivesByPlayer[player][cardId] = nil
		applyModifiers(player, false)
	end

	sendLoadout(player)
end

---------------------------------------------------------------------
-- Players
---------------------------------------------------------------------

local function onPlayerAdded(player)
	equippedPassivesByPlayer[player] = {}

	if TEST_MODE then
		for _, cardId in TEST_LOADOUT do
			equipCard(player, cardId)
		end
	end

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		applyModifiers(player, true)
	end)

	if player.Character then
		applyModifiers(player, true)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	equippedPassivesByPlayer[player] = nil
	activeCardByPlayer[player] = nil
	activeReadyTimeByPlayer[player] = nil
end)

---------------------------------------------------------------------
-- Using the active card
---------------------------------------------------------------------

useActiveCardEvent.OnServerEvent:Connect(function(player)
	local cardId = activeCardByPlayer[player]
	local card = cardId and cardDefinitions[cardId]
	if not card then return end

	-- Cooldown is checked on the server so exploiters can't spam it
	local now = os.clock()
	if now < (activeReadyTimeByPlayer[player] or 0) then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then return end

	-- pcall: a bug inside one card shouldn't break the whole card system
	local success, result = pcall(card.Activate, {
		Player = player,
		Character = character,
		Root = root,
	})
	if not success then
		warn("Error activating", cardId, result)
		return
	end
	if not result then return end -- the card decided not to fire

	local cooldown = result.Cooldown or 0
	activeReadyTimeByPlayer[player] = now + cooldown
	activeCardUsedEvent:FireClient(player, card.ImageId, cooldown, result.ClientEffects or {})
end)

---------------------------------------------------------------------
-- Test only: toggle cards on/off from the client
---------------------------------------------------------------------

toggleCardEvent.OnServerEvent:Connect(function(player, cardId)
	if not TEST_MODE then return end
	if typeof(cardId) ~= "string" or not cardDefinitions[cardId] then return end
	if not equippedPassivesByPlayer[player] then return end

	if isEquipped(player, cardId) then
		unequipCard(player, cardId)
		print(player.Name, "unequipped", cardDefinitions[cardId].DisplayName)
	else
		equipCard(player, cardId)
		print(player.Name, "equipped", cardDefinitions[cardId].DisplayName)
	end
end)
