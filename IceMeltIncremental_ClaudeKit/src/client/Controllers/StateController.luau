--!strict

--[[
	StateController

	Phase 01 scope: completes the handshake and holds the last replicated snapshot. No UI
	— Phase 08 builds the HUD on top of the `changed` signal exposed here.

	The snapshot is display data only. Client code must never compute a reward, price, or
	unlock from it; the server owns all of that. Reading it to decide what to draw is fine,
	and that is all it is for.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 15):WaitForChild("Shared", 15)
local ConfigFolder = Shared:WaitForChild("Config", 15)

local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 15))
local Types = require(Shared:WaitForChild("Types", 15))

local RemoteAccess =
	require(script.Parent.Parent:WaitForChild("Runtime", 15):WaitForChild("RemoteAccess", 15))

type ReplicatedPlayerState = Types.ReplicatedPlayerState

local StateController = {
	Name = "StateController",
	Priority = 10,
}

local current: ReplicatedPlayerState? = nil
local changed = Instance.new("BindableEvent")
local receivedFirstSnapshot = false

--[[
	Last snapshot, or nil before the first one arrives. UI must handle nil rather than
	assuming state exists at construction time.
]]
function StateController.get(): ReplicatedPlayerState?
	return current
end

function StateController.hasState(): boolean
	return receivedFirstSnapshot
end

--[[
	Fires with the new state whenever the server replicates one.
]]
function StateController.getChangedSignal(): RBXScriptSignal
	return changed.Event
end

local function onPlayerState(state: any)
	-- The server is trusted, but a malformed payload should not poison the UI.
	if type(state) ~= "table" then
		warn("[IceMelt] StateController: ignored a non-table PlayerState payload")
		return
	end

	current = state :: ReplicatedPlayerState
	receivedFirstSnapshot = true
	changed:Fire(current)
end

local function onActionResult(result: any)
	if type(result) ~= "table" then
		return
	end
	-- Phase 08 surfaces this in the UI. Until then it is only useful in development.
	local action = tostring((result :: any).Action)
	local status = tostring((result :: any).Status)
	if status ~= "Ok" then
		warn(
			string.format(
				"[IceMelt] action %s -> %s (%s)",
				action,
				status,
				tostring((result :: any).Reason)
			)
		)
	end
end

function StateController.Init()
	RemoteAccess.connect(RemoteNames.Name.PlayerState, onPlayerState)
	RemoteAccess.connect(RemoteNames.Name.ActionResult, onActionResult)
end

--[[
	Bounded retry rather than a single fire-and-forget.

	ClientReady is an event, so if it arrives before the server has connected its listener
	it is dropped silently and the client would sit with no state forever. Retrying a few
	times closes that window. The loop stops the moment a snapshot lands, and gives up
	after a fixed number of attempts rather than waiting indefinitely.

	Retries are safe: the server treats ClientReady as idempotent and rate-limits it.
]]
local HANDSHAKE_ATTEMPTS = 4
local HANDSHAKE_INTERVAL_SECONDS = 0.75

function StateController.Start()
	task.spawn(function()
		for _ = 1, HANDSHAKE_ATTEMPTS do
			if receivedFirstSnapshot then
				return
			end

			RemoteAccess.fire(RemoteNames.Name.ClientReady)
			task.wait(HANDSHAKE_INTERVAL_SECONDS)
		end

		if not receivedFirstSnapshot then
			warn(
				string.format(
					"[IceMelt] StateController: no PlayerState after %d handshake attempts. "
						.. "The server did not answer ClientReady.",
					HANDSHAKE_ATTEMPTS
				)
			)
		end
	end)
end

return StateController
