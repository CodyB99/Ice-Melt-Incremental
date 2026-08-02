--!strict

--[[
	Types

	The shared contract every later phase codes against. Types only — this module holds no
	runtime behaviour and returns an empty frozen table so `require` stays cheap.

	Consumers do:
		local Types = require(path.to.Types)
		type PlayerProfile = Types.PlayerProfile
]]

-- === Content ===============================================================

export type UpgradeKey = "Power" | "Radius" | "Value" | "Speed" | "Crit" | "Luck" | "Auto"

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Secret"

export type ZoneKey = "Backyard" | "Cavern" | "City"

export type UpgradeLevels = {
	Power: number,
	Radius: number,
	Value: number,
	Speed: number,
	Crit: number,
	Luck: number,
	Auto: number,
}

--[[
	How an upgrade's levels turn into a stat.
	  "Multiplier" -> base * (perLevel ^ level)
	  "Additive"   -> base + (perLevel * level)
]]
export type UpgradeScaling = "Multiplier" | "Additive"

export type UpgradeDefinition = {
	Key: UpgradeKey,
	DisplayName: string,
	BaseCost: number,
	Growth: number,
	Cap: number,
	BaseEffect: number,
	PerLevel: number,
	Scaling: UpgradeScaling,
}

export type ToolDefinition = {
	Key: string,
	DisplayName: string,
	Cost: number,
	Power: number,
	Radius: number,
}

export type ZoneDefinition = {
	DisplayName: string,
	Cost: number,
	Durability: number,
	Heat: number,
	RespawnSeconds: number,
	Luck: number,
}

export type DiscoveryDefinition = {
	Key: string,
	DisplayName: string,
	Zone: ZoneKey,
	Rarity: Rarity,
}

export type ChainDefinition = {
	Key: string,
	DisplayName: string,
	Radius: number,
	MaxCells: number,
	Announce: boolean,
}

-- === Persistence ===========================================================

export type PlayerProfile = {
	SchemaVersion: number,
	Heat: number,
	LifetimeHeat: number,
	RunHeat: number,
	Embers: number,
	Thaws: number,
	Upgrades: UpgradeLevels,
	HighestTool: number,
	EquippedTool: number,
	UnlockedZones: { [string]: boolean },
	Discoveries: { [string]: number },
	RewardState: { [string]: any },
	Settings: { [string]: any },
	ReceiptHistory: { [string]: number },
}

--[[
	What the owning client is allowed to see. Deliberately excludes ReceiptHistory and
	every anti-exploit counter; those stay server-only. See docs/02 "Replication".
]]
export type ReplicatedPlayerState = {
	Heat: number,
	Embers: number,
	Thaws: number,
	Upgrades: UpgradeLevels,
	HighestTool: number,
	EquippedTool: number,
	UnlockedZones: { [string]: boolean },
	DiscoveryCount: number,
}

export type ReceiptRecord = {
	PurchaseId: string,
	ProductKey: string,
	GrantedAtUnix: number,
}

-- === Melt protocol =========================================================

--[[
	What a client may ask for. The server derives everything that matters (position, tool,
	power, radius, eligible cells) from authoritative state and treats these as hints only.
]]
export type MeltRequest = {
	Sequence: number,
	ZoneKey: string,
	CellIds: { number },
}

export type MeltCellResult = {
	CellId: number,
	Damage: number,
	Destroyed: boolean,
	Critical: boolean,
}

--[[
	Batched on purpose: one remote per pulse, never one per cell. See docs/02.
]]
export type MeltResult = {
	Sequence: number,
	ZoneKey: string,
	Cells: { MeltCellResult },
	HeatGranted: number,
	DiscoveryKey: string?,
}

export type MeltRejectReason =
	"NoProfile"
	| "NoCharacter"
	| "StaleSequence"
	| "RateLimited"
	| "WrongZone"
	| "OutOfRange"
	| "InvalidPayload"
	| "CapExceeded"

-- === Action results ========================================================

export type ActionStatus = "Ok" | "Denied" | "Error"

export type ActionResult = {
	Action: string,
	Status: ActionStatus,
	Reason: string?,
}

-- === Runtime lifecycle =====================================================

--[[
	Services and controllers are plain tables. `Init` wires dependencies and must not yield
	on another service; `Start` may yield. Both are optional.
]]
export type Service = {
	Name: string,
	Priority: number?,
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
	[any]: any,
}

export type Controller = Service

return table.freeze({})
