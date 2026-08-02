--!strict

--[[
	DevCommandService

	Data reset and testing commands for Development and Test only.

	Gating, in layers:
	  * The service refuses to start at all when the environment is Production, so the
	    entry point does not exist there rather than existing and checking a flag.
	  * The entry point is a BindableFunction in ServerStorage. ServerStorage does not
	    replicate, so no client can see or reach it. It is deliberately not a remote:
	    a client-callable admin channel is exactly what the Phase 01 remote schema forbids.

	Reaching it from the Studio command bar (Server context):

	    local dev = game.ServerStorage.IceMelt.DevCommands
	    dev:Invoke("help")
	    dev:Invoke("get", player.UserId)
	    dev:Invoke("setHeat", player.UserId, 5000)
	    dev:Invoke("save", player.UserId)
	    dev:Invoke("reset", player.UserId)

	A BindableFunction is used rather than requiring this module from the command bar
	because a command-bar `require` returns a fresh module instance with its own state,
	which would not be the running service.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)

local GameConfig = require(ConfigFolder:WaitForChild("GameConfig", 10))
local WorldConfig = require(ConfigFolder:WaitForChild("WorldConfig", 10))

local DataFolder = script.Parent.Parent:WaitForChild("Data", 10)
local ProfileSchema = require(DataFolder:WaitForChild("ProfileSchema", 10))

local DataService = require(script.Parent:WaitForChild("DataService", 10))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService", 10))

local DevCommandService = {
	Name = "DevCommandService",
	Priority = 900,
}

local function resolvePlayer(userId: any): Player?
	if type(userId) ~= "number" then
		return nil
	end
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

local COMMANDS: { [string]: (...any) -> any } = {}

COMMANDS.help = function(): string
	local names = {}
	for name in COMMANDS do
		table.insert(names, name)
	end
	table.sort(names)
	return "DevCommands: " .. table.concat(names, ", ")
end

COMMANDS.backend = function(): string
	return string.format(
		"backend=%s persistent=%s environment=%s store=%s",
		DataService.getBackendName(),
		tostring(DataService.isPersistent()),
		GameConfig.Environment,
		GameConfig.DataStoreName
	)
end

COMMANDS.get = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return "profile not loaded"
	end
	-- A copy, so a command-bar caller cannot mutate live data by accident.
	return {
		SchemaVersion = profile.SchemaVersion,
		Heat = profile.Heat,
		LifetimeHeat = profile.LifetimeHeat,
		RunHeat = profile.RunHeat,
		Embers = profile.Embers,
		Thaws = profile.Thaws,
		Upgrades = table.clone(profile.Upgrades),
		HighestTool = profile.HighestTool,
		EquippedTool = profile.EquippedTool,
		UnlockedZones = table.clone(profile.UnlockedZones),
		Discoveries = table.clone(profile.Discoveries),
		LoadStatus = DataService.getLoadStatus(player),
		Dirty = DataService.isDirty(player),
	}
end

COMMANDS.setHeat = function(userId: any, amount: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	if type(amount) ~= "number" then
		return "amount must be a number"
	end

	local current = PlayerStateService.getHeat(player)
	return PlayerStateService.addHeat(player, amount - current)
end

COMMANDS.addHeat = function(userId: any, amount: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	if type(amount) ~= "number" then
		return "amount must be a number"
	end
	return PlayerStateService.addHeat(player, amount)
end

COMMANDS.save = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	return DataService.save(player)
end

--[[
	Resets the profile to defaults and saves immediately, so the next load sees the reset
	rather than whatever was last written.
]]
COMMANDS.reset = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end

	local profile = DataService.getProfile(player)
	if not profile then
		return "profile not loaded"
	end

	local defaults = ProfileSchema.default()
	for key, value in defaults do
		(profile :: any)[key] = value
	end

	DataService.markDirty(player)
	PlayerStateService.queuePush(player)
	return DataService.save(player)
end

--[[
	Saves, releases the session lock, and loads again: the same round trip a real leave and
	rejoin performs. This is how persistence is verified without stopping the session.
]]
COMMANDS.rejoin = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end

	local before = PlayerStateService.getHeat(player)
	local ok, status = DataService.debugReloadProfile(player)
	local after = PlayerStateService.getHeat(player)

	return {
		Ok = ok,
		Status = status,
		HeatBefore = before,
		HeatAfter = after,
		Preserved = ok and before == after,
	}
end

--[[
	Loads from the store without saving first, so a test can control exactly what the
	loader sees. Use this rather than `rejoin` when the stored record is the thing under
	test, because `rejoin` saves over it before loading.
]]
COMMANDS.loadOnly = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end

	local ok, status = DataService.debugLoadFromStore(player)
	return {
		Ok = ok,
		Status = status,
		Heat = PlayerStateService.getHeat(player),
		LoadStatus = DataService.getLoadStatus(player),
	}
end

--[[
	Exercises the repair path against a deliberately corrupt profile, without touching
	anyone's real data. Returns the repair log so a test can assert on it.
]]
COMMANDS.testRepair = function(): any
	local corrupt = {
		SchemaVersion = "not a number",
		Heat = 0 / 0,
		LifetimeHeat = -50,
		Embers = math.huge,
		Thaws = 2.5,
		Upgrades = { Power = -3, Radius = "x", Crit = 999999 },
		HighestTool = 99,
		EquippedTool = 5,
		UnlockedZones = { Backyard = false, Atlantis = true },
		Discoveries = { FrozenCoin = 2, NotARealThing = 7, ToyCar = -1 },
		ReceiptHistory = "nope",
		RewardState = 12,
		Settings = nil,
	}

	local profile, log = ProfileSchema.normalise(corrupt)
	return {
		RepairCount = #log,
		Repairs = log,
		Result = {
			SchemaVersion = profile.SchemaVersion,
			Heat = profile.Heat,
			Embers = profile.Embers,
			Thaws = profile.Thaws,
			Upgrades = profile.Upgrades,
			HighestTool = profile.HighestTool,
			EquippedTool = profile.EquippedTool,
			UnlockedZones = profile.UnlockedZones,
			Discoveries = profile.Discoveries,
		},
	}
end

function DevCommandService.Start()
	if GameConfig.Environment == "Production" then
		-- Do not create the entry point at all.
		return
	end

	local root = ServerStorage:FindFirstChild(WorldConfig.RootName)
	if not root then
		root = Instance.new("Folder")
		root.Name = WorldConfig.RootName
		root.Parent = ServerStorage
	end
	assert(root ~= nil, "unreachable")

	local existing = root:FindFirstChild("DevCommands")
	if existing then
		existing:Destroy()
	end

	local entry = Instance.new("BindableFunction")
	entry.Name = "DevCommands"
	entry.Parent = root

	entry.OnInvoke = function(command: any, ...)
		if type(command) ~= "string" then
			return "first argument must be a command name"
		end

		local handler = COMMANDS[command]
		if not handler then
			return string.format("unknown command %q. %s", command, COMMANDS.help())
		end

		local ok, result = pcall(handler, ...)
		if not ok then
			return string.format("command %q errored: %s", command, tostring(result))
		end
		return result
	end
end

return DevCommandService
