--!strict

--[[
	ProfileSchema

	Defaults, migrations, and repair for the player profile.

	The governing rule: a profile that fails to parse must never become an empty profile.
	Silently replacing a corrupt field with a default is fine and is what `repair` does;
	silently replacing a whole profile is data loss. Anything `repair` changes is recorded
	and logged by the caller, so a bug that quietly resets players is visible immediately
	instead of after the refund requests start.

	Repair is deliberately conservative. It keeps any value that is plausible, and only
	falls back to the default when a value is the wrong type, non-finite, or outside a
	range that could not have been produced by legitimate play.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)
local UtilFolder = Shared:WaitForChild("Util", 10)

local BalanceConfig = require(ConfigFolder:WaitForChild("BalanceConfig", 10))
local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 10))
local DataConfig = require(ConfigFolder:WaitForChild("DataConfig", 10))
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig", 10))
local Types = require(Shared:WaitForChild("Types", 10))
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

type PlayerProfile = Types.PlayerProfile

local ProfileSchema = {}

local UPGRADE_KEYS = BalanceConfig.UpgradeOrder

--[[
	A brand new player. Everything a later phase reads must exist here, or the first read
	after a fresh join is a nil index.
]]
function ProfileSchema.default(): PlayerProfile
	local upgrades: Types.UpgradeLevels = {
		Power = 0,
		Radius = 0,
		Value = 0,
		Speed = 0,
		Crit = 0,
		Luck = 0,
		Auto = 0,
	}

	local unlockedZones: { [string]: boolean } = {}
	unlockedZones[ContentConfig.StartingZone] = true

	return {
		SchemaVersion = DataConfig.SchemaVersion,
		Heat = 0,
		LifetimeHeat = 0,
		RunHeat = 0,
		Embers = 0,
		Thaws = 0,
		Upgrades = upgrades,
		HighestTool = ContentConfig.StartingToolIndex,
		EquippedTool = ContentConfig.StartingToolIndex,
		UnlockedZones = unlockedZones,
		Discoveries = {},
		RewardState = {},
		Settings = {},
		ReceiptHistory = {},
	}
end

-- === Migrations ============================================================

--[[
	MIGRATIONS[n] upgrades a profile from version n to version n + 1.

	Rules for adding one:
	  * Never delete a field a previous version wrote until at least one release has
	    passed, so a rollback does not destroy data.
	  * Migrations must be pure and must not assume the profile is otherwise valid;
	    `repair` runs afterwards and will clean up anything left malformed.

	Empty at version 1. The machinery is here now so the first real migration is a data
	change rather than an architecture change.
]]
local MIGRATIONS: { [number]: (data: any) -> any } = {}

--[[
	Steps a profile up to the current schema version. Returns the migrated table and a log
	of what ran.
]]
function ProfileSchema.migrate(data: any): (any, { string }, boolean)
	local log: { string } = {}

	if type(data) ~= "table" then
		return data, log, false
	end

	local version = data.SchemaVersion
	if not Validate.isIntegerInRange(version, 0, 1000) then
		-- Unknown version. Treat as the oldest so every migration gets a chance to run,
		-- rather than assuming it is current and skipping fixes.
		table.insert(
			log,
			string.format("SchemaVersion was %s; treating as version 0", tostring(version))
		)
		version = 0
		data.SchemaVersion = 0
	end

	if version > DataConfig.SchemaVersion then
		-- A profile written by a newer build than this server. Refusing here is not enough
		-- on its own: repair would still strip fields this build does not know about, and
		-- the next save would write that stripped version back. The caller must abandon the
		-- load entirely, which is what the third return value signals.
		table.insert(
			log,
			string.format(
				"profile is version %d but this server understands %d; refusing to downgrade",
				version,
				DataConfig.SchemaVersion
			)
		)
		return data, log, true
	end

	while version < DataConfig.SchemaVersion do
		local migration = MIGRATIONS[version]
		if not migration then
			table.insert(log, string.format("no migration from version %d; stopping", version))
			break
		end

		data = migration(data)
		version += 1
		data.SchemaVersion = version
		table.insert(log, string.format("migrated %d -> %d", version - 1, version))
	end

	return data, log, false
end

-- === Repair ================================================================

local function repairNumber(
	value: any,
	fallback: number,
	min: number,
	max: number,
	label: string,
	repairs: { string }
): number
	if Validate.isFiniteInRange(value, min, max) then
		return value
	end
	table.insert(
		repairs,
		string.format("%s was %s, reset to %s", label, tostring(value), tostring(fallback))
	)
	return fallback
end

local function repairInteger(
	value: any,
	fallback: number,
	min: number,
	max: number,
	label: string,
	repairs: { string }
): number
	if Validate.isIntegerInRange(value, min, max) then
		return value
	end
	table.insert(
		repairs,
		string.format("%s was %s, reset to %s", label, tostring(value), tostring(fallback))
	)
	return fallback
end

local function repairTable(value: any, label: string, repairs: { string }): { [string]: any }
	if type(value) == "table" then
		return value
	end
	table.insert(repairs, string.format("%s was %s, reset to an empty table", label, typeof(value)))
	return {}
end

--[[
	Returns a profile guaranteed to satisfy PlayerProfile, plus a list of what changed.
	An empty list means the stored profile was already valid.
]]
function ProfileSchema.repair(data: any): (PlayerProfile, { string })
	local repairs: { string } = {}
	local defaults = ProfileSchema.default()

	if type(data) ~= "table" then
		table.insert(repairs, string.format("profile was %s, replaced with defaults", typeof(data)))
		return defaults, repairs
	end

	local limits = GameConfig.Limits

	-- Repair normalises to the current schema shape by construction, so the profile it
	-- returns is a current-version profile and is stamped as one. Without this a corrupt
	-- version pins the profile at 0 forever and re-logs a migration warning on every load.
	-- A profile from a newer build never reaches here: migrate flags it and the caller
	-- abandons the load rather than letting repair strip fields it does not know.
	if data.SchemaVersion ~= DataConfig.SchemaVersion then
		table.insert(
			repairs,
			string.format(
				"SchemaVersion was %s, stamped as %d after repair",
				tostring(data.SchemaVersion),
				DataConfig.SchemaVersion
			)
		)
	end

	local profile: PlayerProfile = {
		SchemaVersion = DataConfig.SchemaVersion,
		Heat = repairNumber(data.Heat, 0, 0, limits.MaxHeat, "Heat", repairs),
		LifetimeHeat = repairNumber(
			data.LifetimeHeat,
			0,
			0,
			math.huge - 1,
			"LifetimeHeat",
			repairs
		),
		RunHeat = repairNumber(data.RunHeat, 0, 0, math.huge - 1, "RunHeat", repairs),
		Embers = repairNumber(data.Embers, 0, 0, limits.MaxEmbers, "Embers", repairs),
		Thaws = repairInteger(data.Thaws, 0, 0, 1e9, "Thaws", repairs),
		Upgrades = defaults.Upgrades,
		HighestTool = repairInteger(
			data.HighestTool,
			ContentConfig.StartingToolIndex,
			1,
			#ContentConfig.Tools,
			"HighestTool",
			repairs
		),
		EquippedTool = repairInteger(
			data.EquippedTool,
			ContentConfig.StartingToolIndex,
			1,
			#ContentConfig.Tools,
			"EquippedTool",
			repairs
		),
		UnlockedZones = defaults.UnlockedZones,
		Discoveries = {},
		RewardState = repairTable(data.RewardState, "RewardState", repairs),
		Settings = repairTable(data.Settings, "Settings", repairs),
		ReceiptHistory = {},
	}

	-- Upgrades: every key must exist and be a whole number within its configured cap.
	local storedUpgrades = repairTable(data.Upgrades, "Upgrades", repairs)
	local upgrades: Types.UpgradeLevels = table.clone(defaults.Upgrades)
	for _, key in UPGRADE_KEYS do
		local definition = BalanceConfig.Upgrades[key]
		local cap = if definition then definition.Cap else DataConfig.MaxUpgradeLevel
		upgrades[key] = repairInteger(storedUpgrades[key], 0, 0, cap, "Upgrades." .. key, repairs)
	end
	profile.Upgrades = upgrades

	-- Unlocked zones: only known zone keys, and the starting zone is always unlocked or
	-- the player spawns with nowhere legal to be.
	local storedZones = repairTable(data.UnlockedZones, "UnlockedZones", repairs)
	local zones: { [string]: boolean } = {}
	for key, unlocked in storedZones do
		if type(key) == "string" and ContentConfig.Zones[key] ~= nil and unlocked == true then
			zones[key] = true
		elseif type(key) == "string" and ContentConfig.Zones[key] == nil then
			table.insert(repairs, string.format("UnlockedZones had unknown zone %q, dropped", key))
		end
	end
	if not zones[ContentConfig.StartingZone] then
		if next(storedZones) ~= nil then
			table.insert(repairs, "starting zone was not unlocked, re-unlocked")
		end
		zones[ContentConfig.StartingZone] = true
	end
	profile.UnlockedZones = zones

	-- Discoveries: known keys only, counts are whole and positive.
	local storedDiscoveries = repairTable(data.Discoveries, "Discoveries", repairs)
	local knownDiscoveries: { [string]: boolean } = {}
	for _, discovery in ContentConfig.Discoveries do
		knownDiscoveries[discovery.Key] = true
	end
	local discoveries: { [string]: number } = {}
	for key, count in storedDiscoveries do
		if type(key) ~= "string" or not knownDiscoveries[key] then
			table.insert(
				repairs,
				string.format("Discoveries had unknown key %q, dropped", tostring(key))
			)
			continue
		end
		if Validate.isIntegerInRange(count, 1, DataConfig.MaxDiscoveryCount) then
			discoveries[key] = count
		else
			table.insert(
				repairs,
				string.format("Discoveries.%s was %s, dropped", key, tostring(count))
			)
		end
	end
	profile.Discoveries = discoveries

	-- Receipt history: bounded, and pruned oldest-first when over the cap.
	local storedReceipts = repairTable(data.ReceiptHistory, "ReceiptHistory", repairs)
	local receiptKeys: { string } = {}
	for key, stamp in storedReceipts do
		if type(key) == "string" and Validate.isFiniteNumber(stamp) then
			table.insert(receiptKeys, key)
		end
	end
	if #receiptKeys > DataConfig.MaxReceiptHistory then
		table.sort(receiptKeys, function(a: string, b: string): boolean
			return (storedReceipts[a] :: number) > (storedReceipts[b] :: number)
		end)
		table.insert(
			repairs,
			string.format(
				"ReceiptHistory had %d entries, pruned to the newest %d",
				#receiptKeys,
				DataConfig.MaxReceiptHistory
			)
		)
	end
	local receipts: { [string]: number } = {}
	for index, key in receiptKeys do
		if index > DataConfig.MaxReceiptHistory then
			break
		end
		receipts[key] = storedReceipts[key]
	end
	profile.ReceiptHistory = receipts

	-- Cross-field consistency: an equipped tool the player has not unlocked would let a
	-- tampered profile grant a tool's stats for free.
	if profile.EquippedTool > profile.HighestTool then
		table.insert(
			repairs,
			string.format(
				"EquippedTool %d exceeded HighestTool %d, clamped",
				profile.EquippedTool,
				profile.HighestTool
			)
		)
		profile.EquippedTool = profile.HighestTool
	end

	if profile.LifetimeHeat < profile.RunHeat then
		table.insert(repairs, "LifetimeHeat was below RunHeat, raised to match")
		profile.LifetimeHeat = profile.RunHeat
	end

	return profile, repairs
end

--[[
	The load path: migrate, then repair.

	Returns the profile, a combined log, and whether the stored profile came from a newer
	build. When that third value is true the profile returned must NOT be saved: the caller
	is expected to abandon the load. Repairing and saving a newer profile silently discards
	whatever fields this build has never heard of.
]]
function ProfileSchema.normalise(data: any): (PlayerProfile, { string }, boolean)
	local migrated, migrationLog, tooNew = ProfileSchema.migrate(data)
	local profile, repairLog = ProfileSchema.repair(migrated)

	local combined: { string } = {}
	table.move(migrationLog, 1, #migrationLog, 1, combined)
	table.move(repairLog, 1, #repairLog, #combined + 1, combined)

	return profile, combined, tooNew
end

return table.freeze(ProfileSchema)
