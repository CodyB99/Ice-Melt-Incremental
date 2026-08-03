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

--[[
	Playtest milestone timing.

	docs/03 says not to tune from formulas and to record real playtest timestamps. This is the
	stopwatch for that: services report a milestone the first time a player reaches it, and the
	elapsed seconds since that player's run started are kept so a human run can be read off
	directly instead of being reconstructed from pulse counts afterwards.

	Development and Test only, and first-wins so a repeat cannot overwrite a real timing.
]]
local runStart: { [Player]: number } = {}
local milestones: { [Player]: { [string]: number } } = {}

function AnalyticsService.beginRun(player: Player)
	runStart[player] = os.clock()
	milestones[player] = {}
end

function AnalyticsService.markMilestone(player: Player, name: string)
	local started = runStart[player]
	if not started then
		return
	end
	local marks = milestones[player]
	if not marks then
		marks = {}
		milestones[player] = marks
	end
	if marks[name] then
		return
	end

	local elapsed = os.clock() - started
	marks[name] = elapsed

	if GameConfig.Debug.VerboseStartup then
		print(
			string.format(
				"[IceMelt] MILESTONE %-14s %s  at %6.1fs (%.2f min)",
				name,
				player.Name,
				elapsed,
				elapsed / 60
			)
		)
	end
end

function AnalyticsService.getMilestones(player: Player): { [string]: number }
	return table.clone(milestones[player] or {})
end

function AnalyticsService.getRunSeconds(player: Player): number
	local started = runStart[player]
	return if started then os.clock() - started else 0
end

function AnalyticsService.clearRun(player: Player)
	runStart[player] = nil
	milestones[player] = nil
end

function AnalyticsService.Start()
	local Players = game:GetService("Players")
	local DataService = require(script.Parent:WaitForChild("DataService", 10))

	-- The stopwatch starts when a profile is ready to play, not when the player connects,
	-- so load time is not charged against the pacing targets.
	DataService.getLoadedSignal():Connect(function(player: Player)
		AnalyticsService.beginRun(player)
	end)

	Players.PlayerRemoving:Connect(AnalyticsService.clearRun)
end

return AnalyticsService
