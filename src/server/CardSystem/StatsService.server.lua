local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Damage = require(script.Parent:WaitForChild("Damage"))

-- Tuning values (not on the wiki, adjust to taste)
local BASE_WALK_SPEED = 16
local SPRINT_SPEED = 26
local MAX_STAMINA = 100
local STAMINA_DRAIN_PER_SECOND = 20             -- full bar lasts 5 seconds of sprinting
local STAMINA_REGEN_PER_SECOND = 15
local STAMINA_REGEN_DELAY = 1                   -- wait after sprinting before refilling
local EXHAUSTION_RECOVERY = 30                  -- stamina needed to sprint again after hitting 0
local EXHAUSTED_SPRINT_DAMAGE_PER_SECOND = 10   -- HP cost of sprinting at 0 stamina (card)
local BASE_HEALTH_REGEN_PER_SECOND = 1
local STILL_THRESHOLD = 0.1                     -- below this MoveDirection counts as standing still

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
local setSprintingEvent = getOrCreate(remotesFolder, "RemoteEvent", "SetSprinting")

-- [player] = { wantsToSprint, stamina, exhausted, lastSprintTime }
local stateByPlayer = {}

local function resetState(state)
	state.stamina = MAX_STAMINA
	state.exhausted = false
	state.lastSprintTime = 0
end

local function onPlayerAdded(player)
	local state = { wantsToSprint = false }
	resetState(state)
	stateByPlayer[player] = state

	player:SetAttribute("MaxStamina", MAX_STAMINA)

	-- Fresh stamina on every respawn
	player.CharacterAdded:Connect(function()
		resetState(state)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	stateByPlayer[player] = nil
end)

-- The client only says "I want to sprint"; the server decides if it actually can
setSprintingEvent.OnServerEvent:Connect(function(player, wantsToSprint)
	local state = stateByPlayer[player]
	if state and typeof(wantsToSprint) == "boolean" then
		state.wantsToSprint = wantsToSprint
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	local now = os.clock()

	for player, state in stateByPlayer do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then continue end

		local isMoving = humanoid.MoveDirection.Magnitude > STILL_THRESHOLD
		local canSprintWhenExhausted = player:GetAttribute("CanSprintWhenExhausted") == true
		local hasStaminaToSprint = state.stamina > 0 and not state.exhausted

		local isSprinting = state.wantsToSprint
			and isMoving
			and (hasStaminaToSprint or canSprintWhenExhausted)

		local isPayingWithHealth = isSprinting and state.stamina <= 0

		-- Stamina
		if isSprinting then
			state.lastSprintTime = now
			if state.stamina > 0 then
				state.stamina = math.max(state.stamina - STAMINA_DRAIN_PER_SECOND * deltaTime, 0)
				if state.stamina == 0 then
					state.exhausted = true
				end
			else
				-- Only reachable with Survival of the Fittest: sprinting costs HP instead
				Damage.apply(humanoid, EXHAUSTED_SPRINT_DAMAGE_PER_SECOND * deltaTime)
			end
		elseif now - state.lastSprintTime >= STAMINA_REGEN_DELAY then
			state.stamina = math.min(state.stamina + STAMINA_REGEN_PER_SECOND * deltaTime, MAX_STAMINA)
			if state.exhausted and state.stamina >= EXHAUSTION_RECOVERY then
				state.exhausted = false
			end
		end

		humanoid.WalkSpeed = if isSprinting then SPRINT_SPEED else BASE_WALK_SPEED

		-- Health regen (replaces Roblox's default "Health" script)
		local canRegen = humanoid.Health > 0
			and humanoid.Health < humanoid.MaxHealth
			and not isPayingWithHealth
		if canRegen then
			local regenMultiplier = if isMoving
				then 1
				else (player:GetAttribute("StillRegenMultiplier") or 1)
			humanoid.Health = math.min(
				humanoid.Health + BASE_HEALTH_REGEN_PER_SECOND * regenMultiplier * deltaTime,
				humanoid.MaxHealth
			)
		end

		-- Published for the stamina bar on the client
		player:SetAttribute("Stamina", state.stamina)
		player:SetAttribute("Exhausted", state.exhausted)
		player:SetAttribute("IsSprinting", isSprinting)
	end
end)
