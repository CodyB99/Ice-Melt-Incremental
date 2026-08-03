--!strict

local EnvironmentConfig = require(script.Parent.EnvironmentConfig)

local environment = EnvironmentConfig.Current

return table.freeze({
	GameName = "Ice Melt Incremental",

	-- Resolved once by EnvironmentConfig. Never re-derive the mode from RunService.
	Environment = environment.Name,
	EnvironmentReason = environment.Reason,
	DataStoreName = environment.DataStoreName,
	DataStoreNames = EnvironmentConfig.DataStoreNames,

	SchemaVersion = 1,

	Debug = table.freeze({
		-- Development-only startup logging. Silent in Production.
		VerboseStartup = not environment.IsProduction,
		ShowMeltDiagnostics = environment.Name == "Development",
		AssertInvariants = not environment.IsProduction,
	}),

	Limits = table.freeze({
		MaxHeat = 1e15,
		MaxEmbers = 1e9,
		MaxCellsPerPulse = 64,
		MaxMeltPulsesPerSecond = 12,

		--[[
			Chain ceilings.

			These are security limits, not tuning knobs, which is why they live here rather
			than beside the chain definitions in ContentConfig. A cap that lives in the file a
			designer edits to tune content is not a cap.

			MaxCellsPerChainEvent equals the largest configured chain today, so this ratifies
			existing content rather than changing it. MaxChainEventsPerPulse is the important
			one: without it, every destroyed cell in a 64-cell pulse could be a seed, which
			would be 64 x 120 cells per pulse, twelve times a second, per player.
		]]
		MaxCellsPerChainEvent = 120,
		MaxChainEventsPerPulse = 1,
		MaxCellsPerResult = 192,

		--[[
			Announcement budget. Consumed player-first then server, never the reverse, so a
			failed per-player check cannot burn a scarce global token.
		]]
		MaxAnnouncementsPerPlayerBurst = 2,
		AnnouncementsPerPlayerPerSecond = 1 / 30,
		MaxAnnouncementsPerServerBurst = 3,
		AnnouncementsPerServerPerSecond = 0.1,
	}),
})
