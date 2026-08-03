--!strict

--[[
	DiscoveryMath

	The weighted discovery roll, as pure functions.

	Shared rather than living inside DiscoveryService for one concrete reason: the strongest
	new configuration check — proving the weight table is finite, non-negative and positively
	summed at sampled luck values — has to evaluate the same function the roll uses. If the
	maths lived on the server, ConfigAudit would need a second copy of the rule it exists to
	catch, which is the drift it was written to prevent.

	Nothing here yields, allocates a Player, or touches RNG. Callers supply the [0, 1) values,
	which is what lets a dev command run two hundred thousand samples with no player and no
	state, and what makes the whole roll reproducible in a test.

	Two properties this file is responsible for, both acceptance criteria:

	  * A discovery is only ever obtainable in its own zone. The weight table is built over
	    the rarities that actually exist in the current zone, so an absent tier is never given
	    weight at all rather than being rolled and then filtered.
	  * Luck cannot produce invalid weights. Luck is clamped into [MinLuck, MaxLuck] first,
	    every weight is clamped afterwards, and Common's luck exponent is exactly zero so no
	    amount of luck can drive it toward nothing.
]]

local BalanceConfig = require(script.Parent.Parent.Config.BalanceConfig)
local ContentConfig = require(script.Parent.Parent.Config.ContentConfig)
local Types = require(script.Parent.Parent.Types)
local Validate = require(script.Parent.Validate)

--[[
	Rarity is a plain `string` throughout this module rather than the `Types.Rarity` union.

	Luau widens a singleton union back to `string` when it is read out of a mutable table, so
	carrying the union through the lookup tables here would mean a cast at every read — and a
	cast is precisely where a bad value would slip through unnoticed. The union stays where it
	actually catches typos: on `DiscoveryDefinition.Rarity`, authored through ContentConfig's
	typed `discovery()` constructor. This mirrors how `ZoneKey` is already handled — a union at
	the definition, a `string` in the services.

	Runtime safety comes from ConfigAudit instead, which fails the build if any rarity in
	RarityOrder lacks a weight, a luck exponent or a presentation entry.
]]
type DiscoveryDefinition = Types.DiscoveryDefinition

local DiscoveryMath = {}

export type WeightRow = {
	Rarity: string,
	BaseWeight: number,
	Weight: number,
	Probability: number,
}

--[[
	Discoveries in a zone, grouped by rarity. Built once at require time: the catalogue is
	frozen, so there is nothing to invalidate.
]]
local zonePools: { [string]: { [string]: { DiscoveryDefinition } } } = {}
local zoneRarityOrder: { [string]: { string } } = {}

do
	for _, zoneKey in ContentConfig.ZoneOrder do
		zonePools[zoneKey] = {}
	end

	for _, discovery in ContentConfig.Discoveries do
		local pool = zonePools[discovery.Zone]
		if pool then
			local bucket = pool[discovery.Rarity]
			if not bucket then
				bucket = {}
				pool[discovery.Rarity] = bucket
			end
			table.insert(bucket, discovery)
		end
	end

	-- Deterministic ordering within a rarity, so a given roll always picks the same item.
	for _, pool in zonePools do
		for _, bucket in pool do
			table.sort(bucket, function(a: DiscoveryDefinition, b: DiscoveryDefinition): boolean
				return a.Key < b.Key
			end)
		end
	end

	-- Rarities present in each zone, in the configured order rather than pairs() order.
	for zoneKey, pool in zonePools do
		local present: { string } = {}
		for _, rarity in BalanceConfig.Discovery.RarityOrder do
			local bucket = pool[rarity]
			if bucket and #bucket > 0 then
				table.insert(present, rarity)
			end
		end
		zoneRarityOrder[zoneKey] = present
	end
end

function DiscoveryMath.zoneRarities(zoneKey: string): { string }
	return zoneRarityOrder[zoneKey] or {}
end

function DiscoveryMath.zoneDiscoveries(zoneKey: string, rarity: string): { DiscoveryDefinition }
	local pool = zonePools[zoneKey]
	return if pool then (pool[rarity] or {}) else {}
end

--[[
	Clamped luck. Every entry point runs its input through this, so a NaN, an infinity or a
	negative that somehow reached a stat block degrades to the documented baseline rather
	than poisoning the weight table.
]]
function DiscoveryMath.safeLuck(luck: number): number
	local discovery = BalanceConfig.Discovery
	return Validate.clampFinite(luck, discovery.MinLuck, discovery.MaxLuck)
end

--[[
	The weight table for a zone at a given luck, already normalised into probabilities.

	Only rarities present in the zone appear. Their combined probability is exactly 1, so an
	absent tier's share is redistributed across the tiers that do exist rather than being
	rolled and rejected.
]]
function DiscoveryMath.rarityRows(zoneKey: string, luck: number): { WeightRow }
	local discovery = BalanceConfig.Discovery
	local safe = DiscoveryMath.safeLuck(luck)
	local commonKey = discovery.RarityOrder[1]

	local rows: { WeightRow } = {}
	local total = 0

	for _, rarity in DiscoveryMath.zoneRarities(zoneKey) do
		local base = discovery.RarityWeights[rarity] or 0
		local exponent = discovery.RarityLuckExponent[rarity] or 0

		local weight = Validate.clampFinite(base * (safe ^ exponent), 0, discovery.MaxRarityWeight)

		-- The floor that makes "luck must never drive Common to zero" structural.
		if rarity == commonKey then
			weight = math.max(weight, discovery.MinCommonWeight)
		end

		total += weight

		-- Annotated rather than inserted inline: assigning a singleton-typed value into an
		-- unannotated table literal widens it back to `string` and loses the Rarity union.
		local row: WeightRow = {
			Rarity = rarity,
			BaseWeight = base,
			Weight = weight,
			Probability = 0,
		}
		table.insert(rows, row)
	end

	if total <= 0 then
		-- Unreachable with a valid catalogue, because Common is floored above. Falling back
		-- to a flat distribution keeps a corrupt table from producing a divide by zero.
		local share = if #rows > 0 then 1 / #rows else 0
		for _, row in rows do
			row.Probability = share
		end
		return rows
	end

	for _, row in rows do
		row.Probability = row.Weight / total
	end
	return rows
end

--[[
	Picks a rarity from `roll01`, which the caller supplies from its own RNG.
	Returns nil only when the zone has no discoveries at all, which ConfigAudit rejects.
]]
function DiscoveryMath.pickRarity(zoneKey: string, luck: number, roll01: number): string?
	local rows = DiscoveryMath.rarityRows(zoneKey, luck)
	if #rows == 0 then
		return nil
	end

	local target = Validate.clampFinite(roll01, 0, 1)
	local cumulative = 0
	for _, row in rows do
		cumulative += row.Probability
		if target < cumulative then
			return row.Rarity
		end
	end

	-- Floating point can leave the final cumulative a hair under 1.
	return rows[#rows].Rarity
end

--[[
	Picks a specific discovery, from the rolled rarity, within the zone.

	When the rolled rarity somehow has no entry in this zone the fallback steps DOWN the
	rarity order toward commoner tiers, never up and never into another zone. Stepping up
	would hand the player a rarer prize than they rolled, which is a loot exploit wearing the
	shape of a bug fix; leaving the zone would break the acceptance criterion outright. There
	is deliberately no reroll loop: against a corrupt table that is an unbounded server loop.
]]
function DiscoveryMath.pickDiscovery(
	zoneKey: string,
	luck: number,
	roll01: number,
	tie01: number
): DiscoveryDefinition?
	local rarity = DiscoveryMath.pickRarity(zoneKey, luck, roll01)
	if not rarity then
		return nil
	end

	local order = BalanceConfig.Discovery.RarityOrder
	local startIndex = 1
	for index, key in order do
		if key == rarity then
			startIndex = index
			break
		end
	end

	for index = startIndex, 1, -1 do
		local bucket = DiscoveryMath.zoneDiscoveries(zoneKey, order[index])
		if #bucket > 0 then
			local pickIndex = math.floor(Validate.clampFinite(tie01, 0, 0.9999999) * #bucket) + 1
			return bucket[math.clamp(pickIndex, 1, #bucket)]
		end
	end

	return nil
end

--[[
	Probability that an event crediting `cells` destroyed cells yields a discovery.

	Mathematically identical to rolling each cell independently and stopping at the first hit,
	which is what makes the rate a property of how much ice was destroyed rather than of how
	often the client pulsed. A per-pulse roll would be a client-controlled rate, the same
	class of bug Phase 04 already fixed once for damage.
]]
function DiscoveryMath.chanceForCells(cells: number): number
	local discovery = BalanceConfig.Discovery
	local credited = Validate.clampFinite(math.floor(cells), 0, discovery.MaxCreditedCellsPerEvent)
	if credited <= 0 then
		return 0
	end
	return 1 - (1 - discovery.BaseChancePerCell) ^ credited
end

--[[
	Heat for a discovery, in zone-cell-equivalents. The caller multiplies by whatever one cell
	is worth to that player in that zone, so no absolute Heat figure appears here.
]]
function DiscoveryMath.rewardCells(rarity: string, isFirst: boolean): number
	local discovery = BalanceConfig.Discovery
	local cells = discovery.DuplicateHeatCells[rarity] or 0
	if isFirst then
		cells *= discovery.FirstOfKindMultiplier
	end
	return cells
end

function DiscoveryMath.announces(rarity: string): boolean
	return BalanceConfig.Discovery.AnnouncedRarities[rarity] == true
end

--[[
	Catalogue lookup by key. Used by the award path to validate a key before anything is
	granted, and by the client to render a reveal without trusting the payload for anything
	but the key itself.
]]
local byKey: { [string]: DiscoveryDefinition } = {}
for _, discovery in ContentConfig.Discoveries do
	byKey[discovery.Key] = discovery
end
table.freeze(byKey)

function DiscoveryMath.get(key: string): DiscoveryDefinition?
	return byKey[key]
end

return table.freeze(DiscoveryMath)
