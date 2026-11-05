-- Physical Enhancement Jizo (Passive, Legendary)
-- Wiki: +75 max HP and double HP regen while standing still.
-- Does NOT stack with other health increasing cards (handled by CardService rules).
return {
	DisplayName = "Physical Enhancement Jizo",
	Type = "Passive",
	ImageId = "rbxassetid://101126868437432", -- original card art
	Modifiers = {
		MaxHealthBonus = 75,
		StillRegenMultiplier = 2,
	},
}
