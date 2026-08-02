--!strict

--[[
	PlayerStateService

	Phase 01 scope: the join handshake and a state-ready signal. No persistence, no
	economy, no gameplay — Phase 02 replaces the in-memory defaults with real profiles
	loaded through DataService, keeping this module's public shape.

	What it already gets right, so Phase 02 inherits it rather than retrofitting it:
	  * Clients receive a ReplicatedPlayerState, never a profile. ReceiptHistory and every
	    anti-exploit counter stay server-side by construction.
	  * getState returns a copy. A caller cannot mutate another player's state by holding
	    onto the table it was handed.
	  * ClientReady is rate-limited per player and idempotent, so replaying it does nothing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)
local UtilFolder = Shared:WaitForChild("Util", 10)

local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 10))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 10))
local Types = require(Shared:WaitForChild("Types", 10))
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

local RemoteRegistry =
	require(script.Parent.Parent:WaitForChild("Runtime", 10):WaitForChild("RemoteRegistry", 10))

type ReplicatedPlayerState = Types.ReplicatedPlayerState

local PlayerStateService = {
	Name = "PlayerStateService",
	-- Runs early: later services will read state during their own Init.
	Priority = 10,
}

local states: { [Player]: ReplicatedPlayerState } = {}
local readyPlayers: { [Player]: boolean } = {}
local readyBuckets: { [Player]: Validate.TokenBucket } = {}

local function defaultState(): ReplicatedPlayerState
	local unlockedZones: { [string]: boolean } = {}
	unlockedZones[ContentConfig.StartingZone] = true

	return {
		Heat = 0,
		Embers = 0,
		Thaws = 0,
		Upgrades = { Power = 0, Radius = 0, Value = 0, Speed = 0, Crit = 0, Luck = 0, Auto = 0 },
		HighestTool = ContentConfig.StartingToolIndex,
		EquippedTool = ContentConfig.StartingToolIndex,
		UnlockedZones = unlockedZones,
		DiscoveryCount = 0,
	}
end

--[[
	Deep-ish copy. The nested tables are the only mutable parts of the snapshot, so copying
	them is enough to stop a caller mutating the authoritative table.
]]
local function copyState(state: ReplicatedPlayerState): ReplicatedPlayerState
	return {
		Heat = state.Heat,
		Embers = state.Embers,
		Thaws = state.Thaws,
		Upgrades = table.clone(state.Upgrades),
		HighestTool = state.HighestTool,
		EquippedTool = state.EquippedTool,
		UnlockedZones = table.clone(state.UnlockedZones),
		DiscoveryCount = state.DiscoveryCount,
	}
end

function PlayerStateService.getState(player: Player): ReplicatedPlayerState?
	local state = states[player]
	if not state then
		return nil
	end
	return copyState(state)
end

function PlayerStateService.isReady(player: Player): boolean
	return readyPlayers[player] == true
end

--[[
	Pushes the current snapshot to its owner. Only ever sent to the player it describes.
]]
function PlayerStateService.push(player: Player)
	local state = states[player]
	if not state then
		return
	end
	RemoteRegistry.fireClient(RemoteNames.Name.PlayerState, player, copyState(state))
end

local function onPlayerAdded(player: Player)
	states[player] = defaultState()
	-- Sized for the client's bounded handshake retry (4 attempts, 0.75s apart) plus a
	-- rejoin, while still throttling a client that spams the channel.
	readyBuckets[player] = Validate.newTokenBucket(3, 0.5, os.clock())
end

local function onPlayerRemoving(player: Player)
	states[player] = nil
	readyPlayers[player] = nil
	readyBuckets[player] = nil
end

--[[
	The client says its controllers are running; the server answers with the first
	snapshot. Idempotent and rate-limited, so replaying it costs nothing.
]]
local function onClientReady(player: Player)
	local bucket = readyBuckets[player]
	if not bucket or not Validate.consumeToken(bucket, os.clock()) then
		return
	end

	if not states[player] then
		-- Joined and left within the handshake window.
		return
	end

	readyPlayers[player] = true
	PlayerStateService.push(player)
end

function PlayerStateService.Init()
	RemoteRegistry.connect(RemoteNames.Name.ClientReady, onClientReady)
end

function PlayerStateService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Players can already be present when a Studio server starts.
	for _, player in Players:GetPlayers() do
		if not states[player] then
			onPlayerAdded(player)
		end
	end
end

return PlayerStateService
