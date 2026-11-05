local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

-- Same damage pipeline the cards use, so "damage taken" multipliers apply here too
local Damage = require(ServerScriptService:WaitForChild("CardSystem"):WaitForChild("Damage"))

local KILLER_FOLDER = workspace:WaitForChild("Enemies")

-- Tuning values (adjust to taste)
local CONTACT_DAMAGE = 25 -- HP per hit
local HIT_RANGE = 5       -- distance from the killer's center that counts as a hit
local HIT_COOLDOWN = 1    -- seconds before the same killer can hit the same player again

-- [killer] = { [player] = os.clock() time of the last hit }
local lastHitTimes = {}

RunService.Heartbeat:Connect(function()
	-- Idle killers (aggressive mode off, see EnemyChase) don't hurt anyone
	if workspace:GetAttribute("KillersActive") ~= true then return end

	local now = os.clock()

	for _, killer in KILLER_FOLDER:GetChildren() do
		if not killer:IsA("BasePart") then continue end

		-- A killer that was just flung by the Burst can't hit anyone
		if now < (killer:GetAttribute("StunnedUntil") or 0) then continue end

		local hitTimes = lastHitTimes[killer]
		if not hitTimes then
			hitTimes = {}
			lastHitTimes[killer] = hitTimes
		end

		for _, player in Players:GetPlayers() do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not humanoid or not root or humanoid.Health <= 0 then continue end

			local isInRange = (root.Position - killer.Position).Magnitude <= HIT_RANGE
			local canHitAgain = now - (hitTimes[player] or -math.huge) >= HIT_COOLDOWN

			if isInRange and canHitAgain then
				hitTimes[player] = now
				Damage.apply(humanoid, CONTACT_DAMAGE)
			end
		end
	end
end)

-- Cleanup so the table doesn't keep references to things that no longer exist
KILLER_FOLDER.ChildRemoved:Connect(function(killer)
	lastHitTimes[killer] = nil
end)

Players.PlayerRemoving:Connect(function(player)
	for _, hitTimes in lastHitTimes do
		hitTimes[player] = nil
	end
end)
