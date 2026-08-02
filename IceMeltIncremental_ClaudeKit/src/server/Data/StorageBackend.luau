--!strict

--[[
	StorageBackend

	One `update` primitive over DataStore, plus an in-memory stand-in.

	Everything goes through UpdateAsync, never Get/SetAsync. UpdateAsync reads and writes
	inside a single transaction, which is the only way the session-lock check and the
	write it guards cannot be interleaved with another server doing the same thing.

	A transform returning nil aborts the write and leaves the stored value untouched. That
	is how a lock conflict declines to write rather than clobbering another server's data.

	The memory backend exists because Studio without API access throws on every DataStore
	call, which would otherwise block all local development. It is never silently chosen:
	DataService logs which backend is live, and a non-persistent backend warns.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local DataConfig = require(Shared:WaitForChild("Config", 10):WaitForChild("DataConfig", 10))

export type UpdateResult = {
	Ok: boolean,
	Value: any,
	Err: string?,
	Aborted: boolean,
	Attempts: number,
}

export type Backend = {
	Name: string,
	Persistent: boolean,
	update: (
		key: string,
		transform: (any) -> any?,
		attempts: number,
		backoffBase: number
	) -> UpdateResult,
}

local StorageBackend = {}

--[[
	Probes whether DataStore writes actually work here.

	Studio reports API access through a thrown error on first use, not a queryable flag, so
	the only reliable probe is an attempt. Done once at startup against a throwaway key.
]]
function StorageBackend.isDataStoreAvailable(): (boolean, string?)
	local ok, err = pcall(function()
		local store = DataStoreService:GetDataStore("IceMelt_Availability_v1")
		store:UpdateAsync("probe", function(previous)
			return (previous or 0) + 1
		end)
	end)

	if ok then
		return true, nil
	end
	return false, tostring(err)
end

local function backoffDelay(attempt: number, base: number): number
	local delay = base * (2 ^ (attempt - 1))
	return math.min(delay, DataConfig.LoadBackoffMaxSeconds)
end

--[[
	Real DataStore backend.

	Retries only transient failures. A transform that aborts is a decision, not an error,
	so it is returned immediately rather than retried.
]]
function StorageBackend.dataStore(storeName: string): Backend
	local store = DataStoreService:GetDataStore(storeName)

	local function update(
		key: string,
		transform: (any) -> any?,
		attempts: number,
		backoffBase: number
	): UpdateResult
		local lastError: string? = nil

		for attempt = 1, attempts do
			local aborted = false
			local ok, result = pcall(function()
				return store:UpdateAsync(key, function(previous)
					local next = transform(previous)
					if next == nil then
						aborted = true
					end
					return next
				end)
			end)

			if ok then
				return {
					Ok = not aborted,
					Value = result,
					Err = if aborted then "aborted by transform" else nil,
					Aborted = aborted,
					Attempts = attempt,
				}
			end

			lastError = tostring(result)

			if attempt < attempts then
				task.wait(backoffDelay(attempt, backoffBase))
			end
		end

		return { Ok = false, Value = nil, Err = lastError, Aborted = false, Attempts = attempts }
	end

	return {
		Name = string.format("DataStore(%s)", storeName),
		Persistent = true,
		update = update,
	}
end

--[[
	In-memory stand-in with the same contract. Survives for the life of the server only.
]]
function StorageBackend.memory(reason: string): Backend
	local values: { [string]: any } = {}

	local function update(
		key: string,
		transform: (any) -> any?,
		_attempts: number,
		_backoffBase: number
	): UpdateResult
		local ok, result = pcall(transform, values[key])
		if not ok then
			return { Ok = false, Value = nil, Err = tostring(result), Aborted = false, Attempts = 1 }
		end

		if result == nil then
			return {
				Ok = false,
				Value = values[key],
				Err = "aborted by transform",
				Aborted = true,
				Attempts = 1,
			}
		end

		values[key] = result
		return { Ok = true, Value = result, Err = nil, Aborted = false, Attempts = 1 }
	end

	return {
		Name = string.format("Memory(%s)", reason),
		Persistent = false,
		update = update,
	}
end

--[[
	Picks a backend. Prefers the real store; falls back to memory only when DataStore is
	genuinely unusable, and never falls back on a live server, where a silent
	non-persistent backend would destroy real progress.
]]
function StorageBackend.resolve(storeName: string): Backend
	local available, err = StorageBackend.isDataStoreAvailable()

	if available then
		return StorageBackend.dataStore(storeName)
	end

	if not RunService:IsStudio() then
		-- Live and unable to reach DataStore. Fail loudly and still return a real backend:
		-- retries may succeed later, and pretending to save is worse than failing to.
		warn(
			string.format(
				"[IceMelt] DataStore is unavailable on a live server (%s). Continuing with the real "
					.. "backend so saves retry rather than silently going to memory.",
				tostring(err)
			)
		)
		return StorageBackend.dataStore(storeName)
	end

	warn(
		"[IceMelt] Studio API access is disabled, so DataStore cannot be used. "
			.. "Falling back to a NON-PERSISTENT in-memory store: progress will be lost when you stop the "
			.. "session. Enable Game Settings > Security > Studio Access to API Services to test saving."
	)
	return StorageBackend.memory("Studio API access disabled")
end

return table.freeze(StorageBackend)
