--!strict

--[[
	Balance baseline from docs/03_ECONOMY_AND_BALANCE.md.

	Cost of the next level:   floor(BaseCost * Growth ^ currentLevel)
	Stat from levels:
	    Scaling = "Multiplier" -> BaseEffect * (PerLevel ^ level)
	    Scaling = "Additive"   -> BaseEffect + (PerLevel * level)

	Documented order of operations for melt damage, so later phases cannot drift:
	    damagePerSecond = PowerStat * ToolPower
	    damageThisPulse = damagePerSecond * secondsSinceLastPulse
	    heat            = CellHeat * ValueStat * ZoneHeat * CritMultiplier (if critical)
	Radius and luck are resolved the same way and clamped by Limits before use.

	Power is a per-second rate, matching docs/03. MeltService scales it by elapsed time
	rather than applying it once per pulse, so the melt rate does not change with pulse
	frequency and a faster client gains nothing.

	Crit caps at 44 levels: 3% + 44 * 0.5% = 25%, matching the 25% ceiling in docs/03.

	Compounding
	-----------
	Power and Value carry Growth values below the ones tabulated in docs/03 (1.32 and 1.38).
	Every track as documented had cost growth exceeding effect growth, so each level paid back
	more slowly than the one before it and income decelerated. An incremental needs the
	opposite. Setting Growth equal to PerLevel on the two main income tracks makes the time to
	afford the next level roughly constant, which turns income into an exponential in play time
	rather than a curve that flattens.

	Only these two moved, and only the cost column. Every effect, cap, base cost and price in
	docs/03 is untouched, so the shape of the game is unchanged. docs/03 states its figures are
	"initial tuning values", which is the licence being used here; the table in that file has
	been updated to match, with the original values recorded.

	Measured against these values, the pacing targets in docs/01 are approached but not all
	met, and the simulation used to pick them is not trustworthy enough to tune further. Real
	playtest timings belong in PROJECT_STATUS.md and should be what any further change is
	based on.
]]

local Types = require(script.Parent.Parent.Types)

type UpgradeDefinition = Types.UpgradeDefinition

local UPGRADES: { [string]: UpgradeDefinition } = table.freeze({
	Power = table.freeze({
		Key = "Power" :: Types.UpgradeKey,
		DisplayName = "Melt Power",
		BaseCost = 15,
		-- Growth lowered from the 1.32 in docs/03 to match PerLevel exactly. See the
		-- "Compounding" note in this file's header.
		Growth = 1.16,
		Cap = 100,
		BaseEffect = 10,
		PerLevel = 1.16,
		Scaling = "Multiplier" :: Types.UpgradeScaling,
	}),
	Radius = table.freeze({
		Key = "Radius" :: Types.UpgradeKey,
		DisplayName = "Melt Radius",
		BaseCost = 60,
		Growth = 1.55,
		Cap = 45,
		BaseEffect = 4.5,
		PerLevel = 0.45,
		Scaling = "Additive" :: Types.UpgradeScaling,
	}),
	Value = table.freeze({
		Key = "Value" :: Types.UpgradeKey,
		DisplayName = "Heat Value",
		BaseCost = 25,
		-- Lowered from 1.38 to match PerLevel exactly. See the "Compounding" note above.
		Growth = 1.12,
		Cap = 100,
		BaseEffect = 1,
		PerLevel = 1.12,
		Scaling = "Multiplier" :: Types.UpgradeScaling,
	}),
	Speed = table.freeze({
		Key = "Speed" :: Types.UpgradeKey,
		DisplayName = "Walk Speed",
		BaseCost = 100,
		Growth = 1.7,
		Cap = 20,
		BaseEffect = 16,
		PerLevel = 0.75,
		Scaling = "Additive" :: Types.UpgradeScaling,
	}),
	Crit = table.freeze({
		Key = "Crit" :: Types.UpgradeKey,
		DisplayName = "Critical Melt",
		BaseCost = 250,
		Growth = 1.65,
		Cap = 44,
		BaseEffect = 0.03,
		PerLevel = 0.005,
		Scaling = "Additive" :: Types.UpgradeScaling,
	}),
	Luck = table.freeze({
		Key = "Luck" :: Types.UpgradeKey,
		DisplayName = "Discovery Luck",
		BaseCost = 500,
		Growth = 1.75,
		Cap = 40,
		BaseEffect = 1,
		PerLevel = 1.08,
		Scaling = "Multiplier" :: Types.UpgradeScaling,
	}),
	Auto = table.freeze({
		Key = "Auto" :: Types.UpgradeKey,
		DisplayName = "Auto-Melt",
		BaseCost = 2500,
		Growth = 1.8,
		Cap = 20,
		BaseEffect = 0,
		PerLevel = 0.1,
		Scaling = "Additive" :: Types.UpgradeScaling,
	}),
})

return table.freeze({
	Upgrades = UPGRADES,

	-- Build order for UI and for deterministic iteration. Never iterate the map directly
	-- where order matters; pairs() order is not stable.
	UpgradeOrder = table.freeze({ "Power", "Radius", "Value", "Speed", "Crit", "Luck", "Auto" }),

	Melt = table.freeze({
		CriticalMultiplier = 3,
		-- Hard ceilings applied after every multiplier, so no combination of upgrades,
		-- passes, and boosts can produce an absurd single reward.
		MaxRadiusStuds = 40,
		MaxHeatPerPulse = 1e12,
	}),

	Thaw = table.freeze({
		BaseRequirement = 1_000_000,
		EmberExponent = 0.55,
		EmberMultiplier = 0.15,
		EmberMultiplierExponent = 0.65,
	}),

	Discovery = table.freeze({
		-- Baseline weights from docs/04. Adjusted by zone luck, then normalised.
		RarityWeights = table.freeze({
			Common = 55,
			Uncommon = 25,
			Rare = 12,
			Epic = 5.5,
			Legendary = 2,
			Secret = 0.5,
		}),
		RarityOrder = table.freeze({
			"Common",
			"Uncommon",
			"Rare",
			"Epic",
			"Legendary",
			"Secret",
		}),
		-- Luck scales the rare end only; it must never be able to drive Common to zero.
		MinCommonWeight = 1,
	}),
})
