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
	--[[
		Zone this chain can arm in, or nil for any zone. docs/04 calls the Unstable Reactor a
		"rare city chain", so that restriction lives in configuration where ConfigAudit can
		enforce it, rather than staying prose.
	]]
	Zone: ZoneKey?,
}

--[[
	What the server broadcasts for a Legendary/Secret discovery or an announced chain.

	Deliberately a pure value table of catalogue keys and a display name, with no numbers at
	all: no UserId, no Heat, no Ember or luck value, no position, no count, and no free text.
	The client composes every visible string locally from ContentConfig and refuses to render
	a key it does not recognise. That makes "announcements reveal no sensitive data" checkable
	by iterating the payload rather than by reading the call sites.
]]
export type AnnouncementKind = "Discovery" | "Chain"

export type AnnouncementPayload = {
	Kind: AnnouncementKind,
	Key: string,
	-- Plain strings rather than the unions, matching how ZoneKey is already carried on
	-- MeltResult: Luau widens a singleton union read out of a mutable table, so the union
	-- belongs at the definition rather than on the wire.
	Rarity: string?,
	ZoneKey: string,
	PlayerName: string,
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
	Final derived stats, computed once on the server and replicated as finished numbers.

	The client could recompute these from Upgrades with the shared StatMath, but then two
	places would decide what a stat means and a future pass, boost, or cap would have to be
	applied in both. Sending the finished values keeps one authority.
]]
export type DerivedStats = {
	Damage: number,
	Radius: number,
	HeatMultiplier: number,
	CritChance: number,
	Luck: number,
	WalkSpeed: number,
	AutoRate: number,
	EmberMultiplier: number,
}

--[[
	What a Thaw would award right now, and what it would cost the player.

	The Token is an intent nonce for replay protection, not a promise: the award is always
	recomputed at confirmation time from live state, so a stale token cannot lock in a
	larger payout than the player currently deserves.
]]
export type ThawPreview = {
	Eligible: boolean,
	RunHeat: number,
	Required: number,
	EmberAward: number,
	CurrentEmbers: number,
	CurrentMultiplier: number,
	ProjectedMultiplier: number,
	Token: string?,
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
	--[[
		The player's own collection, key to count.

		Deliberately published, unlike every other profile field held back by the allow-list:
		a collection index has to know which of the twenty are owned to draw silhouettes and
		per-zone completion, and this is the player's own progress rather than an anti-exploit
		counter or anything about anyone else. Bounded at twenty keys by the catalogue.
	]]
	Discoveries: { [string]: number },
	Stats: DerivedStats,
	-- Where the server believes the player is. Derived from position, never from a claim.
	CurrentZone: string,
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
	-- Destroyed by chain propagation rather than by the player's melt radius.
	Chain: boolean?,
}

--[[
	Batched on purpose: one remote per pulse, never one per cell. See docs/02.

	Chains and discoveries ride this same batch rather than getting remotes of their own, so
	a 120-cell chain is still exactly one message.

	`ChainOriginCellId` is a cell id, never a Vector3, and `ChainKey` names one of the three
	configured chains rather than carrying a radius. Both follow the rule that no coordinate
	and no free number crosses the wire: the client resolves the id to a real cell part it
	already knows about, so a malformed result cannot place a 48-stud effect anywhere it likes.
]]
export type MeltResult = {
	Sequence: number,
	ZoneKey: string,
	Cells: { MeltCellResult },
	HeatGranted: number,
	DiscoveryKey: string?,
	DiscoveryIsNew: boolean?,
	ChainKey: string?,
	ChainOriginCellId: number?,
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
