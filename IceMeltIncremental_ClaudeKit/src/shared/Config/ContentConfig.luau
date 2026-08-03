--!strict

--[[
	Content catalogue from docs/04_CONTENT_CATALOG.md: 8 tools, 3 zones, 20 discoveries,
	3 chain-reaction objects.

	docs/04 lists the discoveries per zone and a global rarity distribution but does not
	map one to the other. The per-discovery Rarity values below are a first pass chosen so
	each zone spans several tiers and the rarest tiers sit in the later zones. Tune from
	live data; nothing in code depends on a specific assignment.
]]

local Types = require(script.Parent.Parent.Types)

type ToolDefinition = Types.ToolDefinition
type ZoneDefinition = Types.ZoneDefinition
type DiscoveryDefinition = Types.DiscoveryDefinition
type ChainDefinition = Types.ChainDefinition

local TOOLS: { ToolDefinition } = table.freeze({
	table.freeze({ Key = "Match", DisplayName = "Match", Cost = 0, Power = 1.0, Radius = 0 }),
	table.freeze({
		Key = "Candle",
		DisplayName = "Candle",
		-- Lowered from the 350 in docs/03. Measured at 6.16 minutes against a 2-4 minute
		-- target; this and the Backyard Heat rise share the correction between income and
		-- price rather than putting all of it on one value.
		Cost = 280,
		Power = 1.35,
		Radius = 0.25,
	}),
	table.freeze({ Key = "Torch", DisplayName = "Torch", Cost = 2500, Power = 1.85, Radius = 0.5 }),
	table.freeze({
		Key = "Blowtorch",
		DisplayName = "Blowtorch",
		Cost = 18000,
		Power = 2.6,
		Radius = 0.75,
	}),
	table.freeze({
		Key = "Flamethrower",
		DisplayName = "Flamethrower",
		Cost = 125000,
		Power = 3.8,
		Radius = 1.25,
	}),
	table.freeze({
		Key = "HeatCannon",
		DisplayName = "Heat Cannon",
		Cost = 900000,
		Power = 5.8,
		Radius = 1.75,
	}),
	table.freeze({
		Key = "LavaCore",
		DisplayName = "Lava Core",
		Cost = 8000000,
		Power = 9.0,
		Radius = 2.5,
	}),
	table.freeze({
		Key = "MiniSun",
		DisplayName = "Mini Sun",
		Cost = 85000000,
		Power = 15.0,
		Radius = 4.0,
	}),
})

local ZONES: { [string]: ZoneDefinition } = table.freeze({
	Backyard = table.freeze({
		DisplayName = "Frozen Backyard",
		Cost = 0,
		Durability = 10,
		--[[
			Raised from the 1 in docs/03 after a measured playtest: Candle landed at 6.16
			minutes against a 2-4 minute target, so early income was roughly half what the
			documented ladder assumes. Income scales linearly with this value.

			Only the tutorial zone moved. Checked against the zone ladder before changing it:
			by the time a player can afford the Cavern their damage is high enough that
			travel time dominates rather than durability, so the Cavern still pays about ten
			times the Backyard per second and remains clearly worth buying.
		]]
		Heat = 1.5,
		RespawnSeconds = 5,
		Luck = 1.0,
	}),
	Cavern = table.freeze({
		DisplayName = "Ice Cavern",
		Cost = 25000,
		Durability = 250,
		Heat = 30,
		RespawnSeconds = 7,
		Luck = 1.5,
	}),
	City = table.freeze({
		DisplayName = "Frozen City",
		Cost = 5000000,
		Durability = 12000,
		Heat = 1800,
		RespawnSeconds = 9,
		Luck = 2.25,
	}),
})

--[[
	Constructor rather than table literals: Zone and Rarity are string-literal unions, and
	a bare literal in a table widens to `string` and loses the check. Going through typed
	parameters means a typo like "Backyrd" or "Mythic" fails to typecheck at the call site.
]]
local function discovery(
	key: string,
	displayName: string,
	zone: Types.ZoneKey,
	rarity: Types.Rarity
): DiscoveryDefinition
	return table.freeze({ Key = key, DisplayName = displayName, Zone = zone, Rarity = rarity })
end

local DISCOVERIES: { DiscoveryDefinition } = table.freeze({
	-- Frozen Backyard
	discovery("FrozenCoin", "Frozen Coin", "Backyard", "Common"),
	discovery("ToyCar", "Toy Car", "Backyard", "Common"),
	discovery("LostMitten", "Lost Mitten", "Backyard", "Uncommon"),
	discovery("SnowGlobe", "Snow Globe", "Backyard", "Rare"),
	discovery("GoldenKey", "Golden Key", "Backyard", "Epic"),
	discovery("TinyMammoth", "Tiny Mammoth", "Backyard", "Legendary"),

	-- Ice Cavern
	discovery("TrilobiteFossil", "Trilobite Fossil", "Cavern", "Common"),
	discovery("CrystalSkull", "Crystal Skull", "Cavern", "Uncommon"),
	discovery("AncientSword", "Ancient Sword", "Cavern", "Rare"),
	discovery("FrozenExplorer", "Frozen Explorer", "Cavern", "Rare"),
	discovery("DragonEgg", "Dragon Egg", "Cavern", "Epic"),
	discovery("RoyalChest", "Royal Chest", "Cavern", "Legendary"),
	discovery("GlowingCore", "Glowing Core", "Cavern", "Secret"),

	-- Frozen City
	discovery("DiamondWatch", "Diamond Watch", "City", "Common"),
	discovery("FrozenRobot", "Frozen Robot", "City", "Uncommon"),
	discovery("SportsCarKey", "Sports Car Key", "City", "Uncommon"),
	discovery("MeteorFragment", "Meteor Fragment", "City", "Rare"),
	discovery("AlienBeacon", "Alien Beacon", "City", "Epic"),
	discovery("GoldenStatue", "Golden Statue", "City", "Legendary"),
	discovery("SecretPrototype", "Secret Prototype", "City", "Secret"),
})

--[[
	Chain reactions award normal validated rewards with a hard server cap per event, so
	MaxCells is a security limit rather than a tuning knob. See docs/04.
]]
--[[
	Constructor for the same reason `discovery` has one: Zone is a string-literal union, and a
	bare literal in a table widens to `string` and loses the check.
]]
local function chain(
	key: string,
	displayName: string,
	radius: number,
	maxCells: number,
	announce: boolean,
	zone: Types.ZoneKey?
): ChainDefinition
	return table.freeze({
		Key = key,
		DisplayName = displayName,
		Radius = radius,
		MaxCells = maxCells,
		Announce = announce,
		Zone = zone,
	})
end

local CHAINS: { ChainDefinition } = table.freeze({
	chain("HeatPocket", "Heat Pocket", 12, 12, false, nil),
	chain("LavaCapsule", "Lava Capsule", 26, 40, false, nil),
	-- docs/04 calls this "a rare city chain with server announcement", so the zone
	-- restriction is configuration that ConfigAudit enforces rather than prose.
	chain("UnstableReactor", "Unstable Reactor", 48, 120, true, "City"),
})

return table.freeze({
	Tools = TOOLS,
	Zones = ZONES,
	Discoveries = DISCOVERIES,
	Chains = CHAINS,

	-- Deterministic iteration order. pairs() order is not stable, so anything
	-- order-sensitive (UI lists, progression gates, audits) must use this.
	ZoneOrder = table.freeze({ "Backyard", "Cavern", "City" }),

	StartingZone = "Backyard",
	StartingToolIndex = 1,
})
