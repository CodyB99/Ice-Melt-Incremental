--!strict

--[[
	RemoteRegistry

	Creates exactly the remotes declared in RemoteNames, owned entirely by the server.

	Two properties this enforces, both required by the phase acceptance criteria:

	1. Only expected remotes exist. Anything already sitting in the Remotes folder that is
	   not in the schema is destroyed on startup, so a plugin, a stray Rojo sync, or an
	   exploiter's leftover cannot leave a live remote behind.

	2. Direction is enforced. `connect` refuses to attach a server listener to a
	   ServerToClient remote, and `fireClient` refuses to push down a ClientToServer one.
	   Getting this wrong by hand is how an "outbound only" channel quietly becomes an
	   inbound one an exploiter can fire.

	Handlers registered through `connect` are wrapped so a throwing handler warns with the
	remote and player name instead of dropping a bare stack trace with no context.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 10))

local RemoteRegistry = {}

-- Optional value type on purpose: a missing key really is nil, and saying so lets the
-- nil-checks below narrow instead of being rejected as impossible comparisons.
local remotes: { [string]: RemoteEvent? } = {}
local folder: Folder? = nil
local built = false

--[[
	Builds the remote set into `parent`. Idempotent, like the world skeleton: calling it
	again reuses matching instances instead of duplicating them.
]]
function RemoteRegistry.build(parent: Folder): number
	folder = parent

	local expected: { [string]: boolean } = {}
	for _, remoteSpec in RemoteNames.Specs do
		expected[remoteSpec.Name] = true
	end

	-- Remove anything not in the schema before creating, so a stale remote can never
	-- overlap with a new one of the same name but a different class.
	for _, child in parent:GetChildren() do
		if not expected[child.Name] or not child:IsA("RemoteEvent") then
			warn(
				string.format(
					"[IceMelt] RemoteRegistry: removing unexpected object %s (%s) from the Remotes folder",
					child:GetFullName(),
					child.ClassName
				)
			)
			child:Destroy()
		end
	end

	table.clear(remotes)

	local created = 0
	for _, remoteSpec in RemoteNames.Specs do
		local existing = parent:FindFirstChild(remoteSpec.Name)
		local remote: RemoteEvent

		if existing and existing:IsA("RemoteEvent") then
			remote = existing
		else
			if existing then
				existing:Destroy()
			end
			remote = Instance.new("RemoteEvent")
			remote.Name = remoteSpec.Name
			remote.Parent = parent
		end

		remotes[remoteSpec.Name] = remote
		created += 1
	end

	built = true
	return created
end

local function requireBuilt()
	assert(built, "[IceMelt] RemoteRegistry: build() must run before remotes are used")
end

local function specFor(name: string)
	local remoteSpec = RemoteNames.ByName[name]
	assert(remoteSpec ~= nil, string.format("[IceMelt] RemoteRegistry: unknown remote %q", name))
	return remoteSpec
end

function RemoteRegistry.get(name: string): RemoteEvent
	requireBuilt()
	specFor(name)
	local remote = remotes[name]
	assert(
		remote ~= nil,
		string.format("[IceMelt] RemoteRegistry: remote %q was never created", name)
	)
	return remote
end

--[[
	Attaches a server listener to a ClientToServer remote.

	The handler receives (player, ...) exactly as OnServerEvent delivers it. Payload
	validation is the handler's job; this only guarantees the channel is inbound and that
	a throwing handler is reported rather than lost.
]]
-- Handler return type is variadic, not (), so `local ok, err = pcall(handler, ...)` has a
-- second value to bind. Any value a handler returns is ignored.
function RemoteRegistry.connect(
	name: string,
	handler: (Player, ...any) -> ...any
): RBXScriptConnection
	requireBuilt()

	local remoteSpec = specFor(name)
	assert(
		remoteSpec.Direction == "ClientToServer",
		string.format(
			"[IceMelt] RemoteRegistry: %q is %s and must not have a server listener",
			name,
			remoteSpec.Direction
		)
	)

	local remote = RemoteRegistry.get(name)
	return remote.OnServerEvent:Connect(function(player: Player, ...)
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(
				string.format(
					"[IceMelt] remote %s from %s errored: %s",
					name,
					player.Name,
					tostring(err)
				)
			)
		end
	end)
end

function RemoteRegistry.fireClient(name: string, player: Player, ...: any)
	requireBuilt()

	local remoteSpec = specFor(name)
	assert(
		remoteSpec.Direction == "ServerToClient",
		string.format(
			"[IceMelt] RemoteRegistry: %q is %s and cannot be fired at a client",
			name,
			remoteSpec.Direction
		)
	)

	RemoteRegistry.get(name):FireClient(player, ...)
end

function RemoteRegistry.fireAllClients(name: string, ...: any)
	requireBuilt()

	local remoteSpec = specFor(name)
	assert(
		remoteSpec.Direction == "ServerToClient",
		string.format(
			"[IceMelt] RemoteRegistry: %q is %s and cannot be broadcast",
			name,
			remoteSpec.Direction
		)
	)

	RemoteRegistry.get(name):FireAllClients(...)
end

--[[
	Names actually present, for startup logging and tests.
]]
function RemoteRegistry.listNames(): { string }
	local names = {}
	for _, remoteSpec in RemoteNames.Specs do
		if remotes[remoteSpec.Name] then
			table.insert(names, remoteSpec.Name)
		end
	end
	return names
end

function RemoteRegistry.getFolder(): Folder?
	return folder
end

return table.freeze(RemoteRegistry)
