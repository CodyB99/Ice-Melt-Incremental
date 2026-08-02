--!strict

return table.freeze({
	Upgrades = table.freeze({
		Power = table.freeze({ BaseCost = 15, Growth = 1.32, Cap = 100 }),
		Radius = table.freeze({ BaseCost = 60, Growth = 1.55, Cap = 45 }),
		Value = table.freeze({ BaseCost = 25, Growth = 1.38, Cap = 100 }),
		Speed = table.freeze({ BaseCost = 100, Growth = 1.70, Cap = 20 }),
		Crit = table.freeze({ BaseCost = 250, Growth = 1.65, Cap = 44 }),
		Luck = table.freeze({ BaseCost = 500, Growth = 1.75, Cap = 40 }),
		Auto = table.freeze({ BaseCost = 2500, Growth = 1.80, Cap = 20 }),
	}),
	Thaw = table.freeze({
		BaseRequirement = 1_000_000,
		EmberExponent = 0.55,
		EmberMultiplier = 0.15,
		EmberMultiplierExponent = 0.65,
	}),
})
