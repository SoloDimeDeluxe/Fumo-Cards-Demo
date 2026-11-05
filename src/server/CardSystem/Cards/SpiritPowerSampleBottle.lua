-- Spirit Power Sample Bottle (Active, Rare)
-- Wiki: if no killer is within 15 studs -> Scan: white silhouette on every killer,
-- friendly and player on the map (15s cooldown).
-- If a killer is within 15 studs -> Burst: knocks back every killer in 20 studs (60s cooldown).

-- Values taken from the wiki
local DANGER_RADIUS = 15
local BURST_RADIUS = 20
local SCAN_COOLDOWN = 15
local BURST_COOLDOWN = 60

-- Tuning values (not on the wiki)
local SILHOUETTE_DURATION = 5
local FLING_SPEED = 120
local FLING_UPWARD = 60
local FLING_SPIN = 15
local STUN_TIME = 2

local Players = game:GetService("Players")

-- Folders are looked up on each use, so requiring this module never yields
local function getKillers()
	local killers = {}
	local killerFolder = workspace:FindFirstChild("Enemies")
	if killerFolder then
		for _, killer in killerFolder:GetChildren() do
			if killer:IsA("BasePart") then
				table.insert(killers, killer)
			end
		end
	end
	return killers
end

local function isKillerNearby(rootPosition, killers)
	for _, killer in killers do
		if (killer.Position - rootPosition).Magnitude <= DANGER_RADIUS then
			return true
		end
	end
	return false
end

local function burst(root, killers)
	local now = os.clock()
	for _, killer in killers do
		local offset = killer.Position - root.Position
		if offset.Magnitude > BURST_RADIUS then continue end

		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		local direction = if flatOffset.Magnitude > 0.01
			then flatOffset.Unit
			else root.CFrame.LookVector

		-- Stun first so the chase script doesn't overwrite the launch velocity
		killer:SetAttribute("StunnedUntil", now + STUN_TIME)
		killer.AssemblyLinearVelocity = direction * FLING_SPEED + Vector3.yAxis * FLING_UPWARD
		killer.AssemblyAngularVelocity = Vector3.new(
			math.random(-FLING_SPIN, FLING_SPIN),
			math.random(-FLING_SPIN, FLING_SPIN),
			math.random(-FLING_SPIN, FLING_SPIN)
		)
	end
end

-- Everything on the map the Scan reveals: killers, friendlies and other players
local function getScanTargets(user, killers)
	local targets = table.clone(killers)

	local friendlyFolder = workspace:FindFirstChild("Friendlies")
	if friendlyFolder then
		for _, friendly in friendlyFolder:GetChildren() do
			if friendly:IsA("BasePart") or friendly:IsA("Model") then
				table.insert(targets, friendly)
			end
		end
	end

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= user and otherPlayer.Character then
			table.insert(targets, otherPlayer.Character)
		end
	end

	return targets
end

local SpiritPowerSampleBottle = {
	DisplayName = "Spirit Power Sample Bottle",
	Type = "Active",
	ImageId = "rbxassetid://91100588401183",
}

-- Called by CardService when the player uses the card.
-- Returns the cooldown to apply and the effects the client should show.
function SpiritPowerSampleBottle.Activate(context)
	local killers = getKillers()

	if isKillerNearby(context.Root.Position, killers) then
		burst(context.Root, killers)
		return { Cooldown = BURST_COOLDOWN }
	end

	return {
		Cooldown = SCAN_COOLDOWN,
		ClientEffects = {
			Silhouettes = {
				Targets = getScanTargets(context.Player, killers),
				Duration = SILHOUETTE_DURATION,
			},
		},
	}
end

return SpiritPowerSampleBottle
