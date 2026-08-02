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
	}),
})
