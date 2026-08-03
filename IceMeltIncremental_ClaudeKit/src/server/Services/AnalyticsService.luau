--!strict

--[[
	AnalyticsService

	One place every gameplay event is reported to.

	Phase 10 owns real analytics. This exists now so that the events Phase 06 is required to
	log have somewhere to go that is not a scattered set of print calls, and so that adding
	the Roblox AnalyticsService backend later is a change to one function rather than a hunt
	through every service.

	Two rules from docs/08 that are cheap to honour now and expensive to retrofit:
	  * Events are emitted from the server, never the client.
	  * Custom fields stay low-cardinality. No user IDs, no free text, no unbounded keys.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local GameConfig = require(Shared:WaitForChild("Config", 10):WaitForChild("GameConfig", 10))

local AnalyticsService = {
	Name = "AnalyticsService",
	Priority = 5,
}

local counts: { [string]: number } = {}

--[[
	Records one event. `data` is for low-cardinality dimensions and numeric values only.

	In Development the event is printed so a playtest can be followed live. In Production it
	is counted silently until Phase 10 attaches the real sink; logging every event on a live
	server would be pure noise.
]]
function AnalyticsService.logEvent(player: Player?, eventName: string, data: { [string]: any }?)
	counts[eventName] = (counts[eventName] or 0) + 1

	if not GameConfig.Debug.VerboseStartup then
		return
	end

	local parts = {}
	if data then
		for key, value in data do
			table.insert(parts, string.format("%s=%s", key, tostring(value)))
		end
		table.sort(parts)
	end

	print(
		string.format(
			"[IceMelt] analytics %s%s%s",
			eventName,
			if player then " " .. player.Name else "",
			if #parts > 0 then " {" .. table.concat(parts, " ") .. "}" else ""
		)
	)
end

function AnalyticsService.getCounts(): { [string]: number }
	return table.clone(counts)
end

return AnalyticsService
