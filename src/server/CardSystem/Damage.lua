local Players = game:GetService("Players")

local Damage = {}

-- Every damage source should go through here, so "damage taken" multipliers
-- (like Marked for Death in the real game) apply to all of them the same way
function Damage.apply(humanoid, amount)
	if humanoid.Health <= 0 then return end

	local player = Players:GetPlayerFromCharacter(humanoid.Parent)
	local multiplier = (player and player:GetAttribute("DamageTakenMultiplier")) or 1

	humanoid:TakeDamage(amount * multiplier)
end

return Damage
