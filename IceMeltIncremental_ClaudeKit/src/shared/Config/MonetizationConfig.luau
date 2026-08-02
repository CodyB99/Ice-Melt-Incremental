--!strict

-- Replace 0 with IDs created in Creator Dashboard. A zero ID must remain disabled safely.
return table.freeze({
	Passes = table.freeze({
		DoubleHeat = 0,
		DoubleDiscoveryLuck = 0,
		ExpandedRadius = 0,
		AutoMeltPlus = 0,
		VIP = 0,
	}),
	Products = table.freeze({
		StarterHeatPack = 0,
		HeatSurge = 0,
		LuckSurge = 0,
		ServerHeatWave = 0,
		ChainReactionCharge = 0,
		WelcomeBundle = 0,
	}),
})
