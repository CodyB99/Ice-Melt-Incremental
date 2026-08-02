--!strict

--[[
	EnvironmentConfig

	Resolves exactly one environment for this Luau VM and derives the data store name
	from it. Every other module must read the environment from here instead of calling
	RunService:IsStudio() again, so that the mode is explicit and auditable.

	Safety contract (Phase 00 acceptance criterion):
	  * "Production" can never resolve inside Roblox Studio, for any override value.
	  * "Production" only resolves on a live server whose PlaceId is listed in
	    PRODUCTION_PLACE_IDS below.
	  * Anything unrecognised falls back to "Test". The fallback is never "Production",
	    so an unpublished or forgotten place cannot touch live player data.
]]

local RunService = game:GetService("RunService")

export type EnvironmentName = "Development" | "Test" | "Production"

export type Environment = {
	Name: EnvironmentName,
	Reason: string,
	DataStoreName: string,
	IsStudio: boolean,
	IsLiveServer: boolean,
	IsProduction: boolean,
}

local DATA_STORE_NAMES: { [string]: string } = table.freeze({
	Development = "IceMelt_PlayerData_DEV_v1",
	Test = "IceMelt_PlayerData_TEST_v1",
	Production = "IceMelt_PlayerData_PROD_v1",
})

-- Owner action, see docs/11_ROBLOX_DASHBOARD_SETUP.md.
-- Record the published PlaceIds here. Until a PlaceId appears in PRODUCTION_PLACE_IDS
-- no server anywhere can reach the production data store.
local PRODUCTION_PLACE_IDS: { [number]: boolean } = table.freeze({})

-- 87210191828303 (universe 10620948462) is the first published Ice Melt place. It is
-- registered as Test, not Production, so live runs exercise the test data store.
-- Move it to PRODUCTION_PLACE_IDS only when this place becomes the live experience.
local TEST_PLACE_IDS: { [number]: boolean } = table.freeze({
	[87210191828303] = true,
})

-- Local developer override for Studio sessions only.
-- Set to "Test" to exercise the shared test data store from Studio.
-- "Production" is rejected on purpose and downgrades to "Development" with a warning.
local STUDIO_OVERRIDE: EnvironmentName? = nil

-- Branches are written out one literal at a time on purpose: it keeps the return type a
-- true EnvironmentName rather than a widened string, and makes the Production rejection
-- impossible to miss when reading.
local function resolveStudio(): (EnvironmentName, string)
	local override = STUDIO_OVERRIDE

	if override == nil then
		return "Development", "Studio session (default)"
	end

	if override == "Production" then
		warn(
			"[IceMelt] EnvironmentConfig: STUDIO_OVERRIDE is set to Production. "
				.. "Studio may never use production data. Falling back to Development."
		)
		return "Development", "Studio session (rejected Production override)"
	end

	if override == "Test" then
		return "Test", "Studio session (STUDIO_OVERRIDE = Test)"
	end

	return "Development", "Studio session (STUDIO_OVERRIDE = Development)"
end

local function resolveLiveServer(): (EnvironmentName, string)
	local placeId = game.PlaceId

	if PRODUCTION_PLACE_IDS[placeId] then
		return "Production",
			string.format("live server, PlaceId %d is registered as Production", placeId)
	end

	if TEST_PLACE_IDS[placeId] then
		return "Test", string.format("live server, PlaceId %d is registered as Test", placeId)
	end

	return "Test",
		string.format("live server, PlaceId %d is not registered, defaulting to Test", placeId)
end

local isStudio = RunService:IsStudio()
local isLiveServer = RunService:IsServer() and not isStudio

local name: EnvironmentName
local reason: string

if isStudio then
	name, reason = resolveStudio()
else
	-- Live server, or a live client. Clients never touch data stores; they resolve the
	-- same way purely so their debug flags line up with the server's.
	name, reason = resolveLiveServer()
end

-- Only the server should be noisy about an unregistered place.
if isLiveServer and name == "Test" and not TEST_PLACE_IDS[game.PlaceId] then
	warn(
		string.format(
			"[IceMelt] EnvironmentConfig: PlaceId %d is not registered in EnvironmentConfig. "
				.. "Running against the TEST data store (%s). Record the PlaceId before launch.",
			game.PlaceId,
			DATA_STORE_NAMES.Test
		)
	)
end

local dataStoreName = DATA_STORE_NAMES[name]
assert(
	dataStoreName ~= nil,
	"[IceMelt] EnvironmentConfig: no data store name for environment " .. tostring(name)
)

-- Defence in depth. If any future edit breaks the rules above, fail loudly here rather
-- than silently opening production data to a Studio session.
if name == "Production" and isStudio then
	error(
		"[IceMelt] EnvironmentConfig: Production resolved inside Studio. Refusing to continue.",
		0
	)
end

local current: Environment = table.freeze({
	Name = name,
	Reason = reason,
	DataStoreName = dataStoreName,
	IsStudio = isStudio,
	IsLiveServer = isLiveServer,
	IsProduction = name == "Production",
})

return table.freeze({
	Current = current,
	DataStoreNames = DATA_STORE_NAMES,
})
