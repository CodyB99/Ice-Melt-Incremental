--!strict

--[[
	Single source of truth for every CollectionService tag used by the game.
	Services must never type a tag string inline; a typo in a literal fails silently,
	a typo against this table fails at require time.
]]

return table.freeze({
	-- Applied by WorldSkeleton in Phase 00.
	WorldRoot = "IceMelt_WorldRoot",
	Zone = "IceMelt_Zone",
	ZoneGround = "IceMelt_ZoneGround",
	IceField = "IceMelt_IceField",
	Boundary = "IceMelt_Boundary",
	Spawn = "IceMelt_Spawn",
	Sign = "IceMelt_Sign",

	-- Reserved for later phases. Declared now so tag names never drift.
	IceCell = "IceMelt_IceCell", -- Phase 03
	ChainSource = "IceMelt_ChainSource", -- Phase 07
	TravelPad = "IceMelt_TravelPad", -- Phase 05
})
