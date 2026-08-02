--!strict

--[[
	Server bootstrap.

	Fixed startup order, because each step depends on the previous one:
	  1. environment guard   -- refuse to run before anything can touch a data store
	  2. runtime containers  -- folders every later step writes into
	  3. world skeleton      -- placeholder world
	  4. config audit        -- catch content drift before services read the config
	  5. remotes             -- created by the server, from the schema, and nothing else
	  6. services            -- deterministic Init then Start
	  7. one startup line    -- development only

	Phase 02 adds DataService ahead of PlayerStateService in the Services folder; nothing
	in this file needs to change to accommodate it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WAIT = 10

local Shared = ReplicatedStorage:WaitForChild("IceMelt", WAIT):WaitForChild("Shared", WAIT)
local ConfigFolder = Shared:WaitForChild("Config", WAIT)
local UtilFolder = Shared:WaitForChild("Util", WAIT)

local GameConfig = require(ConfigFolder:WaitForChild("GameConfig", WAIT))
local ConfigAudit = require(UtilFolder:WaitForChild("ConfigAudit", WAIT))

local ServerRoot = script.Parent
assert(ServerRoot ~= nil, "[IceMelt] server bootstrap has no parent folder")

local RuntimeFolder = ServerRoot:WaitForChild("Runtime", WAIT)
local RuntimeContainers = require(RuntimeFolder:WaitForChild("RuntimeContainers", WAIT))
local RemoteRegistry = require(RuntimeFolder:WaitForChild("RemoteRegistry", WAIT))
local ServiceRuntime = require(RuntimeFolder:WaitForChild("ServiceRuntime", WAIT))
local WorldSkeleton =
	require(ServerRoot:WaitForChild("World", WAIT):WaitForChild("WorldSkeleton", WAIT))

-- 1. Defence in depth. EnvironmentConfig already refuses to resolve Production inside
-- Studio; if that ever regresses, stop before a single data store call is made.
if GameConfig.Environment == "Production" and RunService:IsStudio() then
	error("[IceMelt] Production environment resolved inside Studio. Refusing to start.", 0)
end

-- 2 and 3.
local containers = RuntimeContainers.ensure()

local worldOk, worldResult = pcall(function()
	return WorldSkeleton.build(containers.WorldRoot)
end)
if not worldOk then
	warn(string.format("[IceMelt] WorldSkeleton.build failed: %s", tostring(worldResult)))
end

-- 4. Content drift produces silently wrong gameplay, so audit before services read it.
local audit = ConfigAudit.run()
ConfigAudit.log(audit, GameConfig.Debug.VerboseStartup)
if audit.ErrorCount > 0 and GameConfig.Debug.AssertInvariants then
	-- Loud in Development and Test, non-fatal in Production: a live server limping with a
	-- logged error beats refusing to let anyone play.
	warn(
		string.format(
			"[IceMelt] configuration has %d error(s). Fix these before shipping.",
			audit.ErrorCount
		)
	)
end

-- 5.
local remoteCount = RemoteRegistry.build(containers.Remotes)

-- 6.
local servicesFolder = ServerRoot:FindFirstChild("Services")
local registered = if servicesFolder then ServiceRuntime.registerFolder(servicesFolder) else 0
local startOrder = ServiceRuntime.start()
local failures = ServiceRuntime.failures()

-- 7. Exactly one line, development only.
if GameConfig.Debug.VerboseStartup then
	print(
		string.format(
			"[%s] server ready | env=%s | store=%s | zones=%d | remotes=%d | services=%d [%s]%s | config=%dE/%dW",
			GameConfig.GameName,
			GameConfig.Environment,
			GameConfig.DataStoreName,
			if worldOk then worldResult.ZonesBuilt else 0,
			remoteCount,
			registered,
			table.concat(startOrder, ", "),
			if #failures > 0 then " FAILED: " .. table.concat(failures, ", ") else "",
			audit.ErrorCount,
			audit.WarningCount
		)
	)
end
