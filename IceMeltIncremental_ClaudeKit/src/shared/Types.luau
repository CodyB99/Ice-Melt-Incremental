--!strict

export type UpgradeLevels = {
	Power: number,
	Radius: number,
	Value: number,
	Speed: number,
	Crit: number,
	Luck: number,
	Auto: number,
}

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

return nil
