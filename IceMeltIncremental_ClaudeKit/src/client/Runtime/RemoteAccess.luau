--!strict

--[[
	RemoteAccess

	The only way client code touches a remote.

	A controller cannot reach a remote that is not in the shared schema: `fire` and
	`connect` resolve the name through RemoteNames.ByName and assert on a miss, so a typo
	or an invented name fails loudly at the call site instead of silently doing nothing.
	Direction is enforced the same way it is on the server, so client code cannot try to
	fire an outbound-only channel.

	This is a correctness and maintainability guard, not a security boundary. Nothing on
	the client can be trusted, which is exactly why the server independently creates only
	the schema's remotes and validates every payload. Both halves are required.

	Every wait here is bounded. A missing Remotes folder means server startup failed, and
	that must surface as an actionable warning rather than an infinite yield.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WAIT_TIMEOUT_SECONDS = 15

local Shared = ReplicatedStorage:WaitForChild("IceMelt", WAIT_TIMEOUT_SECONDS)
	:WaitForChild("Shared", WAIT_TIMEOUT_SECONDS)
local RemoteNames = require(
	Shared:WaitForChild("Config", WAIT_TIMEOUT_SECONDS)
		:WaitForChild("RemoteNames", WAIT_TIMEOUT_SECONDS)
)

local RemoteAccess = {}

local folder: Instance? = nil
local cache: { [string]: RemoteEvent } = {}

--[[
	Resolves the server-created Remotes folder. Returns false when it never appeared, so
	the caller can report a failed handshake instead of hanging.
]]
function RemoteAccess.awaitFolder(timeoutSeconds: number?): boolean
	if folder then
		return true
	end

	local iceMelt = ReplicatedStorage:FindFirstChild("IceMelt")
	if not iceMelt then
		return false
	end

	local found = iceMelt:WaitForChild(RemoteNames.Folder, timeoutSeconds or WAIT_TIMEOUT_SECONDS)
	if not found then
		return false
	end

	folder = found
	return true
end

local function specFor(name: string)
	local remoteSpec = RemoteNames.ByName[name]
	-- The guard the acceptance criterion is about: an unregistered name has no remote and
	-- never will, so asking for one is a bug worth stopping on.
	assert(
		remoteSpec ~= nil,
		string.format("[IceMelt] RemoteAccess: %q is not a declared remote", name)
	)
	return remoteSpec
end

local function resolve(name: string): RemoteEvent?
	local cached = cache[name]
	if cached then
		return cached
	end

	if not folder then
		return nil
	end

	local instance = folder:WaitForChild(name, WAIT_TIMEOUT_SECONDS)
	if not instance or not instance:IsA("RemoteEvent") then
		warn(
			string.format("[IceMelt] RemoteAccess: remote %q is missing or not a RemoteEvent", name)
		)
		return nil
	end

	cache[name] = instance
	return instance
end

--[[
	Fires a ClientToServer remote. Returns false when the remote could not be resolved, so
	callers can degrade rather than error mid-frame.
]]
function RemoteAccess.fire(name: string, ...: any): boolean
	local remoteSpec = specFor(name)
	assert(
		remoteSpec.Direction == "ClientToServer",
		string.format(
			"[IceMelt] RemoteAccess: %q is %s; the client cannot fire it",
			name,
			remoteSpec.Direction
		)
	)

	local remote = resolve(name)
	if not remote then
		return false
	end

	remote:FireServer(...)
	return true
end

--[[
	Listens on a ServerToClient remote.
]]
-- Variadic return type so `local ok, err = pcall(handler, ...)` has a second value to
-- bind. Any value a handler returns is ignored.
function RemoteAccess.connect(name: string, handler: (...any) -> ...any): RBXScriptConnection?
	local remoteSpec = specFor(name)
	assert(
		remoteSpec.Direction == "ServerToClient",
		string.format(
			"[IceMelt] RemoteAccess: %q is %s; the client cannot listen on it",
			name,
			remoteSpec.Direction
		)
	)

	local remote = resolve(name)
	if not remote then
		return nil
	end

	return remote.OnClientEvent:Connect(function(...)
		local ok, err = pcall(handler, ...)
		if not ok then
			warn(string.format("[IceMelt] client handler for %s errored: %s", name, tostring(err)))
		end
	end)
end

return table.freeze(RemoteAccess)
