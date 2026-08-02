--!strict

--[[
	Server bootstrap.

	Phase 00 scope only: resolve the environment, create the runtime containers, build the
	placeholder world, and emit exactly one development-only startup line.

	Phase 01 replaces the body of this script with deterministic service lifecycle
	bootstrapping. Keep the environment guard when that happens.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("IceMelt"):WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig"))

local ServerRoot = script.Parent
assert(ServerRoot ~= nil, "[IceMelt] server bootstrap has no parent folder")

local RuntimeContainers =
	require(ServerRoot:WaitForChild("Runtime"):WaitForChild("RuntimeContainers"))
local WorldSkeleton = require(ServerRoot:WaitForChild("World"):WaitForChild("WorldSkeleton"))

-- Defence in depth. EnvironmentConfig already refuses to resolve Production inside
-- Studio; if that ever regresses, stop before a single data store call is made.
if GameConfig.Environment == "Production" and RunService:IsStudio() then
	error("[IceMelt] Production environment resolved inside Studio. Refusing to start.", 0)
end

local containers = RuntimeContainers.ensure()

local buildOk, buildResult = pcall(function()
	return WorldSkeleton.build(containers.WorldRoot)
end)

if not buildOk then
	warn(string.format("[IceMelt] WorldSkeleton.build failed: %s", tostring(buildResult)))
end

if GameConfig.Debug.VerboseStartup then
	local zonesBuilt = if buildOk then buildResult.ZonesBuilt else 0
	print(
		string.format(
			"[%s] server ready | env=%s (%s) | store=%s | zones=%d | remotes=%s | world=%s",
			GameConfig.GameName,
			GameConfig.Environment,
			GameConfig.EnvironmentReason,
			GameConfig.DataStoreName,
			zonesBuilt,
			containers.Remotes:GetFullName(),
			if buildOk then "ok" else "FAILED"
		)
	)
end
