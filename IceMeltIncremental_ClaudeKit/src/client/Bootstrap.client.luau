--!strict

--[[
	Client bootstrap.

	  1. wait for the shared tree, bounded
	  2. wait for the server-created Remotes folder, bounded
	  3. start controllers deterministically
	  4. one startup line, development only

	Every wait is bounded. A missing container must produce an actionable warning naming
	what was missing, never an indefinite yield that looks like a hang.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WAIT = 15

local iceMelt = ReplicatedStorage:WaitForChild("IceMelt", WAIT)
if not iceMelt then
	warn(
		"[IceMelt] client bootstrap aborted: ReplicatedStorage.IceMelt did not replicate within 15s."
	)
	return
end

local sharedFolder = iceMelt:WaitForChild("Shared", WAIT)
if not sharedFolder then
	warn(
		"[IceMelt] client bootstrap aborted: ReplicatedStorage.IceMelt.Shared did not replicate within 15s."
	)
	return
end

local configFolder = sharedFolder:WaitForChild("Config", WAIT)
if not configFolder then
	warn("[IceMelt] client bootstrap aborted: shared Config folder did not replicate within 15s.")
	return
end

local GameConfig = require(configFolder:WaitForChild("GameConfig", WAIT))

local ClientRoot = script.Parent
assert(ClientRoot ~= nil, "[IceMelt] client bootstrap has no parent folder")

local RuntimeFolder = ClientRoot:WaitForChild("Runtime", WAIT)
local RemoteAccess = require(RuntimeFolder:WaitForChild("RemoteAccess", WAIT))
local ControllerRuntime = require(RuntimeFolder:WaitForChild("ControllerRuntime", WAIT))

-- The Remotes folder is created by the server, so a timeout here is a real signal that
-- server startup failed rather than a client-side race.
local remotesReady = RemoteAccess.awaitFolder(WAIT)
if not remotesReady then
	warn(
		"[IceMelt] client bootstrap: the server's Remotes folder never appeared. "
			.. "Controllers will start, but no request will reach the server."
	)
end

local controllersFolder = ClientRoot:FindFirstChild("Controllers")
local registered = if controllersFolder
	then ControllerRuntime.registerFolder(controllersFolder)
	else 0
local startOrder = ControllerRuntime.start()
local failures = ControllerRuntime.failures()

if GameConfig.Debug.VerboseStartup then
	print(
		string.format(
			"[%s] client ready | env=%s | remotes=%s | controllers=%d [%s]%s",
			GameConfig.GameName,
			GameConfig.Environment,
			if remotesReady then "ok" else "missing",
			registered,
			table.concat(startOrder, ", "),
			if #failures > 0 then " FAILED: " .. table.concat(failures, ", ") else ""
		)
	)
end
