--!strict

--[[
	RuntimeContainers

	Creates every runtime folder the game relies on, from the server, at startup.
	Nothing here may be hand-placed in the Studio Explorer: a manually created folder
	survives a Rojo sync, drifts from source control, and is impossible to audit.

	Layout produced:

	    ReplicatedStorage/IceMelt/Remotes     -- Phase 01 populates
	    ReplicatedStorage/IceMelt/State       -- Phase 02 populates
	    ServerStorage/IceMelt/Pools           -- Phase 03 populates
	    Workspace/IceMelt                     -- WorldSkeleton populates
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("IceMelt"):WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")

local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames"))
local TagNames = require(ConfigFolder:WaitForChild("TagNames"))
local WorldConfig = require(ConfigFolder:WaitForChild("WorldConfig"))

export type Containers = {
	Remotes: Folder,
	ReplicatedState: Folder,
	ServerPools: Folder,
	WorldRoot: Folder,
}

local RuntimeContainers = {}

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("Folder") then
			return existing
		end
		warn(
			string.format(
				"[IceMelt] RuntimeContainers: %s.%s exists as a %s, expected a Folder. Replacing it.",
				parent:GetFullName(),
				name,
				existing.ClassName
			)
		)
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

--[[
	Idempotent. Safe to call more than once; later phases can call it to obtain the
	same folders without risking duplicates.
]]
function RuntimeContainers.ensure(): Containers
	-- ReplicatedStorage.IceMelt is created by Rojo, but never assume it: a partial sync
	-- or a manual delete must produce a warning, not a nil index crash later.
	local iceMeltReplicated = ReplicatedStorage:FindFirstChild(WorldConfig.RootName)
	if not iceMeltReplicated then
		warn(
			string.format(
				"[IceMelt] RuntimeContainers: ReplicatedStorage.%s is missing. "
					.. "Rojo is probably not synced. Creating an empty folder so startup can continue.",
				WorldConfig.RootName
			)
		)
		iceMeltReplicated = ensureFolder(ReplicatedStorage, WorldConfig.RootName)
	end
	assert(iceMeltReplicated ~= nil, "unreachable")

	local iceMeltServer = ensureFolder(ServerStorage, WorldConfig.RootName)

	local containers: Containers = {
		Remotes = ensureFolder(iceMeltReplicated, RemoteNames.Folder),
		ReplicatedState = ensureFolder(iceMeltReplicated, WorldConfig.ReplicatedFolders.State),
		ServerPools = ensureFolder(iceMeltServer, WorldConfig.ServerFolders.Pools),
		WorldRoot = ensureFolder(Workspace, WorldConfig.RootName),
	}

	if not CollectionService:HasTag(containers.WorldRoot, TagNames.WorldRoot) then
		CollectionService:AddTag(containers.WorldRoot, TagNames.WorldRoot)
	end

	return containers
end

return RuntimeContainers
