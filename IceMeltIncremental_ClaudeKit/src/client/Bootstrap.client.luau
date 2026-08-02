--!strict

--[[
	Client bootstrap.

	Phase 00 scope only: wait for the server-created containers with an explicit timeout
	and emit exactly one development-only startup line.

	Every wait here is bounded. A missing container must produce an actionable warning,
	never an indefinite yield that looks like a hang.

	Phase 01 replaces the body of this script with deterministic controller lifecycle
	bootstrapping and the state-ready handshake.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WAIT_TIMEOUT_SECONDS = 15

local iceMelt = ReplicatedStorage:WaitForChild("IceMelt", WAIT_TIMEOUT_SECONDS)
if not iceMelt then
	warn(
		"[IceMelt] client bootstrap aborted: ReplicatedStorage.IceMelt did not replicate within 15s."
	)
	return
end

local sharedFolder = iceMelt:WaitForChild("Shared", WAIT_TIMEOUT_SECONDS)
if not sharedFolder then
	warn(
		"[IceMelt] client bootstrap aborted: ReplicatedStorage.IceMelt.Shared did not replicate within 15s."
	)
	return
end

local configFolder = sharedFolder:WaitForChild("Config", WAIT_TIMEOUT_SECONDS)
if not configFolder then
	warn("[IceMelt] client bootstrap aborted: shared Config folder did not replicate within 15s.")
	return
end

local GameConfig = require(configFolder:WaitForChild("GameConfig"))
local RemoteNames = require(configFolder:WaitForChild("RemoteNames"))

-- The Remotes folder is created by the server, so a timeout here is a real signal that
-- server startup failed rather than a client-side race.
local remotes = iceMelt:WaitForChild(RemoteNames.Folder, WAIT_TIMEOUT_SECONDS)
if not remotes then
	warn(
		string.format(
			"[IceMelt] client bootstrap: %s.%s was not created within 15s. Server bootstrap probably failed.",
			iceMelt:GetFullName(),
			RemoteNames.Folder
		)
	)
end

if GameConfig.Debug.VerboseStartup then
	print(
		string.format(
			"[%s] client ready | env=%s | remotes=%s",
			GameConfig.GameName,
			GameConfig.Environment,
			if remotes then "ok" else "missing"
		)
	)
end
