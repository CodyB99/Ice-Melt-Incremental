--!strict

--[[
	RemoteNames

	The complete, closed list of remotes. The server creates exactly these and nothing
	else; the client can only resolve a name that appears here. Anything not in this table
	does not exist at runtime.

	Every remote is a RemoteEvent. There are deliberately no client-invoked RemoteFunctions:
	a RemoteFunction called from a client parks a server thread until it returns, so a
	malicious client can stall server work just by invoking one. Requests go out as events
	and the server answers on ActionResult or PlayerState.

	Direction is enforced, not documentation:
	  "ClientToServer" -- server connects OnServerEvent; client may fire
	  "ServerToClient" -- server fires to a player; client may only connect

	Naming rule: no generic command/dispatch remote. Each action gets its own name so the
	server never has to trust a client-supplied action string.
]]

export type RemoteDirection = "ClientToServer" | "ServerToClient"

export type RemoteSpec = {
	Name: string,
	Direction: RemoteDirection,
	Description: string,
}

local function spec(name: string, direction: RemoteDirection, description: string): RemoteSpec
	return table.freeze({
		Name = name,
		Direction = direction,
		Description = description,
	})
end

-- Order is the creation order and keeps startup logs stable.
local SPECS: { RemoteSpec } = table.freeze({
	-- Handshake and state
	spec(
		"ClientReady",
		"ClientToServer",
		"Client signals its controllers are running. Once per join."
	),
	spec(
		"PlayerState",
		"ServerToClient",
		"Sanitised state snapshot or delta for the owning player."
	),
	spec(
		"ActionResult",
		"ServerToClient",
		"Ack or denial for a client request, with a reason category."
	),

	-- Melt loop
	spec(
		"MeltPulse",
		"ClientToServer",
		"Requests a heat pulse. Server derives all stats and eligible cells."
	),
	spec(
		"MeltResult",
		"ServerToClient",
		"Batched melt results for visuals. Never one remote per cell."
	),

	-- Progression
	spec("PurchaseUpgrade", "ClientToServer", "Requests one upgrade level."),
	spec("UnlockTool", "ClientToServer", "Requests a tool unlock."),
	spec("EquipTool", "ClientToServer", "Requests an equip of an already unlocked tool."),
	spec("UnlockZone", "ClientToServer", "Requests a zone unlock purchase."),
	spec("TravelZone", "ClientToServer", "Requests travel to an unlocked zone."),

	-- Prestige
	spec("RequestThaw", "ClientToServer", "Asks for a Thaw preview."),
	spec("ConfirmThaw", "ClientToServer", "Confirms the Thaw the player was shown."),

	-- Rewards
	spec("ClaimReward", "ClientToServer", "Claims a daily or playtime reward."),
	spec("RedeemCode", "ClientToServer", "Redeems a promo code."),
})

local byName: { [string]: RemoteSpec } = {}
for _, entry in SPECS do
	assert(byName[entry.Name] == nil, "[IceMelt] RemoteNames: duplicate remote name " .. entry.Name)
	byName[entry.Name] = entry
end
table.freeze(byName)

local names = {}
for _, entry in SPECS do
	names[entry.Name] = entry.Name
end
table.freeze(names)

return table.freeze({
	-- Runtime folder created by the server under ReplicatedStorage.IceMelt.
	Folder = "Remotes",

	Specs = SPECS,
	ByName = byName,

	--[[
		Name constants, so call sites read RemoteNames.Name.MeltPulse instead of a string
		literal. A typo then fails at require time rather than silently doing nothing.
	]]
	Name = names,
})
