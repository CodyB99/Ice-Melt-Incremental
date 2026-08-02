--!strict

--[[
	DataService

	Owns loading, locking, autosaving, and releasing player profiles. Nothing else in the
	codebase touches a DataStore.

	Stored value shape, one key per player:

	    {
	        Data = <PlayerProfile>,
	        Lock = { JobId = string, PlaceId = number, Heartbeat = number } | nil,
	        Meta = { LastSave = number, SaveCount = number },
	    }

	Session lock, and why it is shaped this way:

	  * Load claims the lock inside the same UpdateAsync that reads the profile. Read and
	    claim cannot be interleaved with another server, which is the whole point.
	  * A lock is respected while its Heartbeat is fresh. Autosave refreshes it, so a
	    healthy server keeps its claim.
	  * A stale lock is stolen, not obeyed forever. A crashed server never releases, and
	    without expiry the player could never rejoin.
	  * Save re-checks ownership and aborts if another server has taken over. That is the
	    guarantee that two sessions cannot silently overwrite each other: the loser writes
	    nothing rather than clobbering the winner.

	Failure policy: if a profile cannot be loaded, the player is released with a clear
	message rather than being handed defaults. Handing out defaults and then autosaving
	over a real profile is how save data gets destroyed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)

local DataConfig = require(ConfigFolder:WaitForChild("DataConfig", 10))
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig", 10))
local Types = require(Shared:WaitForChild("Types", 10))

local DataFolder = script.Parent.Parent:WaitForChild("Data", 10)
local ProfileSchema = require(DataFolder:WaitForChild("ProfileSchema", 10))
local StorageBackend = require(DataFolder:WaitForChild("StorageBackend", 10))

type PlayerProfile = Types.PlayerProfile

export type LoadStatus = "Loaded" | "Locked" | "Failed" | "Incompatible"

local DataService = {
	Name = "DataService",
	-- Must initialise before anything that reads player state.
	Priority = 1,
}

local backend: StorageBackend.Backend? = nil
local profiles: { [Player]: PlayerProfile } = {}
local loadStatus: { [Player]: LoadStatus } = {}
local dirty: { [Player]: boolean } = {}
local releasing: { [Player]: boolean } = {}
local shuttingDown = false

--[[
	Identity used for the session lock.

	Studio leaves game.JobId empty. Deriving one from os.time() made every play session
	look like a different server, so stopping and restarting locked the developer out of
	their own profile until the lock expired. A stable per-place id means a restarted
	Studio session recognises the lock as its own and reclaims it immediately.

	This is safe: it only ever applies in Studio, which cannot reach the production store,
	and profiles are keyed per user, so two developers testing with different accounts
	never share a record.
]]
local jobId = if game.JobId ~= "" then game.JobId else "studio-" .. tostring(game.PlaceId)

local function keyFor(userId: number): string
	return DataConfig.KeyPrefix .. tostring(userId)
end

local function lockIsHeldByAnother(lock: any, now: number): boolean
	if type(lock) ~= "table" then
		return false
	end
	if lock.JobId == jobId then
		return false
	end

	local heartbeat = lock.Heartbeat
	if type(heartbeat) ~= "number" then
		-- Malformed lock. Treat as stale rather than blocking the player forever.
		return false
	end

	return (now - heartbeat) < DataConfig.LockTimeoutSeconds
end

--[[
	Loads and claims. Returns the profile plus the status, so the caller can distinguish
	"another server has it" from "the datastore is broken" and act differently.
]]
local function loadProfile(player: Player): (PlayerProfile?, LoadStatus)
	local activeBackend = backend
	if not activeBackend then
		return nil, "Failed"
	end

	local key = keyFor(player.UserId)
	local repairs: { string } = {}
	local blockedByLock = false
	local isNewProfile = false
	local incompatible = false

	for attempt = 1, DataConfig.LoadAttempts do
		blockedByLock = false
		isNewProfile = false
		incompatible = false
		table.clear(repairs)

		local result = activeBackend.update(key, function(stored)
			local now = os.time()

			if lockIsHeldByAnother(stored and stored.Lock, now) then
				blockedByLock = true
				return nil -- abort, do not touch another server's claim
			end

			local container = if type(stored) == "table" then stored else {}
			local profile: PlayerProfile

			if container.Data == nil then
				-- A player with no stored data is new, not corrupt. Logging this as a
				-- repair would bury real corruption in first-join noise.
				profile = ProfileSchema.default()
				isNewProfile = true
			else
				local normalised, log, tooNew = ProfileSchema.normalise(container.Data)
				table.move(log, 1, #log, #repairs + 1, repairs)

				if tooNew then
					-- Written by a newer build. Abort the whole transaction: claiming the
					-- lock or writing a repaired copy would discard fields this build does
					-- not understand.
					incompatible = true
					return nil
				end

				profile = normalised
			end

			container.Data = profile
			container.Lock = { JobId = jobId, PlaceId = game.PlaceId, Heartbeat = now }
			container.Meta = if type(container.Meta) == "table" then container.Meta else {}

			return container
		end, 1, DataConfig.LoadBackoffBaseSeconds)

		if result.Ok and type(result.Value) == "table" then
			if isNewProfile and GameConfig.Debug.VerboseStartup then
				print(string.format("[IceMelt] created a new profile for %s", player.Name))
			end
			if #repairs > 0 then
				-- Every repair is logged. A bug that quietly resets players must be visible.
				for _, entry in repairs do
					warn(string.format("[IceMelt] profile repair for %s: %s", player.Name, entry))
				end
			end
			return result.Value.Data, "Loaded"
		end

		if incompatible then
			-- Not retryable: a newer profile will still be newer next attempt.
			for _, entry in repairs do
				warn(string.format("[IceMelt] profile load for %s: %s", player.Name, entry))
			end
			return nil, "Incompatible"
		end

		if not blockedByLock and result.Err and not result.Aborted then
			warn(
				string.format(
					"[IceMelt] DataService: load attempt %d for %s failed: %s",
					attempt,
					player.Name,
					result.Err
				)
			)
		end

		if attempt < DataConfig.LoadAttempts then
			local delay = math.min(
				DataConfig.LoadBackoffBaseSeconds * (2 ^ (attempt - 1)),
				DataConfig.LoadBackoffMaxSeconds
			)
			task.wait(delay)
			if not player.Parent then
				return nil, "Failed"
			end
		end
	end

	return nil, if blockedByLock then "Locked" else "Failed"
end

--[[
	Writes the profile back, refreshing the lock heartbeat.

	`release` clears the lock so another server can take over immediately, which is what
	makes a fast rejoin work instead of waiting out the lock timeout.
]]
local function saveProfile(player: Player, release: boolean): boolean
	local activeBackend = backend
	local profile = profiles[player]
	if not activeBackend or not profile then
		return false
	end

	local key = keyFor(player.UserId)
	local lostLock = false

	local result = activeBackend.update(key, function(stored)
		local container = if type(stored) == "table" then stored else {}
		local lock = container.Lock

		-- Another server took over while we were playing. Writing here would overwrite
		-- their newer data with ours, so abort instead.
		if type(lock) == "table" and lock.JobId ~= nil and lock.JobId ~= jobId then
			if (os.time() - (tonumber(lock.Heartbeat) or 0)) < DataConfig.LockTimeoutSeconds then
				lostLock = true
				return nil
			end
		end

		local meta = if type(container.Meta) == "table" then container.Meta else {}
		meta.LastSave = os.time()
		meta.SaveCount = (tonumber(meta.SaveCount) or 0) + 1

		container.Data = profile
		container.Meta = meta
		container.Lock = if release
			then nil
			else { JobId = jobId, PlaceId = game.PlaceId, Heartbeat = os.time() }

		return container
	end, DataConfig.SaveAttempts, DataConfig.SaveBackoffBaseSeconds)

	if lostLock then
		warn(
			string.format(
				"[IceMelt] DataService: refusing to save %s; another server holds the session lock. "
					.. "This save was discarded to protect the newer session.",
				player.Name
			)
		)
		return false
	end

	if not result.Ok then
		warn(
			string.format(
				"[IceMelt] DataService: save failed for %s: %s",
				player.Name,
				tostring(result.Err)
			)
		)
		return false
	end

	dirty[player] = false
	return true
end

-- === Public API ============================================================

--[[
	The live profile table, server-only. Callers must not hand this to a client; use
	PlayerStateService for anything client-facing.
]]
function DataService.getProfile(player: Player): PlayerProfile?
	return profiles[player]
end

function DataService.isLoaded(player: Player): boolean
	return loadStatus[player] == "Loaded" and profiles[player] ~= nil
end

function DataService.getLoadStatus(player: Player): LoadStatus?
	return loadStatus[player]
end

--[[
	Marks the profile as needing a save. Mutations should call this rather than saving
	immediately, so a burst of changes costs one write at the next autosave.
]]
function DataService.markDirty(player: Player)
	if profiles[player] then
		dirty[player] = true
	end
end

function DataService.isDirty(player: Player): boolean
	return dirty[player] == true
end

function DataService.save(player: Player): boolean
	return saveProfile(player, false)
end

function DataService.getBackendName(): string
	local activeBackend = backend
	return if activeBackend then activeBackend.Name else "none"
end

function DataService.isPersistent(): boolean
	local activeBackend = backend
	return activeBackend ~= nil and activeBackend.Persistent
end

--[[
	Fires after a profile finishes loading, so services can react without polling.
]]
local loadedEvent = Instance.new("BindableEvent")

--[[
	Development only. Runs the exact save -> release lock -> load -> reclaim lock round
	trip that a real leave and rejoin performs, without needing to leave the session.

	This is the honest way to test persistence in Studio: it goes through the same backend
	calls and the same lock transitions, so a bug in either shows up here.
]]
function DataService.debugReloadProfile(player: Player): (boolean, string)
	if GameConfig.Environment == "Production" then
		return false, "unavailable in Production"
	end
	if not profiles[player] then
		return false, "no profile loaded"
	end

	-- Forward declared below; assigned once the local functions exist.
	return DataService._debugReload(player)
end

function DataService.getLoadedSignal(): RBXScriptSignal
	return loadedEvent.Event
end

-- === Lifecycle =============================================================

local function releaseProfile(player: Player)
	-- Idempotent: PlayerRemoving and BindToClose can both fire for the same player during
	-- a shutdown, and releasing twice would mean a second write after the lock is gone.
	if releasing[player] or not profiles[player] then
		return
	end
	releasing[player] = true

	if profiles[player] then
		saveProfile(player, true)
	end

	profiles[player] = nil
	loadStatus[player] = nil
	dirty[player] = nil
	releasing[player] = nil
end

--[[
	Implementation for DataService.debugReloadProfile, defined here because it needs
	releaseProfile and loadProfile.
]]
--[[
	Development only. Discards the in-memory profile WITHOUT saving, then loads from the
	store. This is the fresh-join path, and it is the only way to test how the loader
	reacts to stored data it did not write, such as a profile from a newer build.

	debugReloadProfile cannot be used for that: it saves first, which would overwrite the
	very record under test.
]]
function DataService.debugLoadFromStore(player: Player): (boolean, string)
	if GameConfig.Environment == "Production" then
		return false, "unavailable in Production"
	end

	profiles[player] = nil
	loadStatus[player] = nil
	dirty[player] = nil

	local profile, status = loadProfile(player)
	if status == "Loaded" and profile ~= nil then
		profiles[player] = profile
		loadStatus[player] = "Loaded"
		dirty[player] = false
		loadedEvent:Fire(player)
		return true, "loaded"
	end

	return false, status
end

function DataService._debugReload(player: Player): (boolean, string)
	releaseProfile(player)

	local profile, status = loadProfile(player)
	if status == "Loaded" and profile ~= nil then
		profiles[player] = profile
		loadStatus[player] = "Loaded"
		dirty[player] = false
		loadedEvent:Fire(player)
		return true, "reloaded"
	end

	return false, status
end

local function onPlayerAdded(player: Player)
	loadStatus[player] = nil

	local profile, status = loadProfile(player)

	if not player.Parent then
		-- Left during the load. Release the claim we may have taken.
		if profile then
			profiles[player] = profile
			releaseProfile(player)
		end
		return
	end

	if status == "Loaded" and profile ~= nil then
		profiles[player] = profile
		loadStatus[player] = "Loaded"
		dirty[player] = false
		loadedEvent:Fire(player)
		return
	end

	-- Either the load failed, or it reported success with no profile, which would be a bug
	-- here rather than a data problem. Both are treated as a failure: the one thing that
	-- must not happen is continuing with a profile we are not sure about.
	local failure: LoadStatus = if status == "Locked"
		then "Locked"
		elseif status == "Incompatible" then "Incompatible"
		else "Failed"
	loadStatus[player] = failure

	-- A user-safe failure path. Defaults would be worse than a kick: the autosave would
	-- write them over a profile that is probably fine.
	local message
	if failure == "Locked" then
		message = "Your save is still in use by another server. Please rejoin in a few seconds."
	elseif failure == "Incompatible" then
		message = "Your save was made by a newer version of this game. "
			.. "Your progress is safe and untouched. Please try again shortly."
	else
		message = "We could not load your save. Please rejoin. No progress has been lost."
	end

	warn(
		string.format(
			"[IceMelt] DataService: %s load ended as %s; removing player",
			player.Name,
			failure
		)
	)
	player:Kick(message)
end

--[[
	No Init. Resolving the backend probes DataStore, which yields, and Init must not yield:
	doing it there let startup continue before `backend` existed, so the first player's load
	ran against a nil backend, failed, and kicked them. Priority 1 means this Start runs
	before any other service's, which is early enough.
]]
function DataService.Start()
	local resolved = StorageBackend.resolve(GameConfig.DataStoreName)
	backend = resolved

	if not resolved.Persistent then
		warn("[IceMelt] DataService: profiles are NOT persistent in this session.")
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		releaseProfile(player)
	end)

	-- Players can already be present when a Studio server starts.
	for _, player in Players:GetPlayers() do
		if loadStatus[player] == nil then
			task.spawn(onPlayerAdded, player)
		end
	end

	-- Autosave and heartbeat. One loop for everyone rather than a timer per player.
	task.spawn(function()
		while not shuttingDown do
			task.wait(DataConfig.AutosaveSeconds)
			if shuttingDown then
				break
			end

			for player, _ in profiles do
				if player.Parent and (dirty[player] or true) then
					-- Saves even when clean, because the write also refreshes the session
					-- lock heartbeat; skipping it would let our own lock go stale.
					saveProfile(player, false)
				end
			end
		end
	end)

	--[[
		Shutdown. BindToClose blocks the server closing for a short grace period, so every
		profile gets one final save and its lock released. Without this, a shutdown during
		play leaves locks held until they expire and the last minute of progress is lost.
	]]
	game:BindToClose(function()
		shuttingDown = true

		-- Nothing to flush when the backend is not persistent.
		if not DataService.isPersistent() then
			return
		end

		-- Count everyone first. Counting inside the spawn loop let an early-finishing
		-- release drive the counter to zero and fire before the loop had queued the rest,
		-- so the wait below could be released while saves were still outstanding.
		local toRelease: { Player } = {}
		for _, player in Players:GetPlayers() do
			if profiles[player] then
				table.insert(toRelease, player)
			end
		end

		if #toRelease == 0 then
			return
		end

		local pending = #toRelease
		local finished = Instance.new("BindableEvent")

		for _, player in toRelease do
			task.spawn(function()
				releaseProfile(player)
				pending -= 1
				if pending <= 0 then
					finished:Fire()
				end
			end)
		end

		-- Bounded: a hung DataStore must not hold the shutdown open indefinitely.
		task.delay(15, function()
			finished:Fire()
		end)
		finished.Event:Wait()
	end)
end

return DataService
