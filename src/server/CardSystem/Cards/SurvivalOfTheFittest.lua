-- Law of the Survival of the Fittest (Passive, Epic)
-- Wiki: lets you keep sprinting while exhausted, but it drains your HP quickly.
-- That exhaustion damage is also boosted by "damage taken" effects (goes through Damage.apply).
return {
	DisplayName = "Law of the Survival of the Fittest",
	Type = "Passive",
	ImageId = "rbxassetid://122511797565828", -- original card art
	Modifiers = {
		CanSprintWhenExhausted = true,
	},
}
