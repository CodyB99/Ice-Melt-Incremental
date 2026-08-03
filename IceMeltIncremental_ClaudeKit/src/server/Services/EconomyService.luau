--!strict

--[[
	EconomyService

	Every Heat and Ember transaction goes through here.

	The single job that matters is `trySpend`: check the balance and deduct in one call,
	with no yield between them. Callers that check affordability, then do other work, then
	deduct, create a window where two requests both pass the check and both deduct — the
	classic double-spend. Making the atomic version the only convenient option removes the
	chance to write that bug.

	It also gives analytics one place to hook every source and sink (docs/08) rather than
	instrumenting each caller in Phase 10.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local UtilFolder = Shared:WaitForChild("Util", 10)
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

local DataService = require(script.Parent:WaitForChild("DataService", 10))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService", 10))

local EconomyService = {
	Name = "EconomyService",
	Priority = 18,
}

-- Totals by source and sink, for the development overlay and for Phase 10 analytics.
local sources: { [string]: number } = {}
local sinks: { [string]: number } = {}

function EconomyService.canAfford(player: Player, cost: number): boolean
	if not Validate.isFiniteNumber(cost) or cost < 0 then
		return false
	end
	return PlayerStateService.getHeat(player) >= cost
end

--[[
	Deducts `cost` if the player can afford it. Returns whether it happened.

	Atomic by construction: the balance read and the deduction happen with no yield
	between them, so two requests in the same frame cannot both succeed on one balance.
]]
function EconomyService.trySpend(player: Player, cost: number, reason: string): boolean
	if not DataService.isLoaded(player) then
		return false
	end

	-- A negative or non-finite cost would credit the player instead of charging them,
	-- which is exactly the shape of a "buy free upgrades" exploit.
	if not Validate.isFiniteNumber(cost) or cost < 0 then
		warn(
			string.format(
				"[IceMelt] EconomyService: rejected spend of %s for %s",
				tostring(cost),
				reason
			)
		)
		return false
	end

	local balance = PlayerStateService.getHeat(player)
	if balance < cost then
		return false
	end

	PlayerStateService.addHeat(player, -cost)
	sinks[reason] = (sinks[reason] or 0) + cost
	return true
end

--[[
	Grants Heat from a named source. Negative grants are rejected: spending must go through
	trySpend so the balance check is never skipped.
]]
function EconomyService.grant(player: Player, amount: number, reason: string): number
	if not DataService.isLoaded(player) then
		return 0
	end
	if not Validate.isFiniteNumber(amount) or amount <= 0 then
		return 0
	end

	sources[reason] = (sources[reason] or 0) + amount
	return PlayerStateService.addHeat(player, amount)
end

function EconomyService.getLedger()
	return {
		Sources = table.clone(sources),
		Sinks = table.clone(sinks),
	}
end

return EconomyService
