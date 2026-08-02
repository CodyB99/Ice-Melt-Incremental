--!strict

--[[
	DataConfig

	Persistence tuning. Every value here is a data-safety decision, so the reasoning lives
	next to the number rather than in a commit message.
]]

return table.freeze({
	-- Bump only alongside a migration in ProfileSchema.MIGRATIONS.
	SchemaVersion = 1,

	KeyPrefix = "Player_",

	--[[
		Session lock. A profile records which server holds it and when that server last
		refreshed the claim.

		LockTimeoutSeconds must be comfortably longer than HeartbeatSeconds, or a healthy
		server's own lock would look stale and a second server could steal a profile that
		is actively being played. It must also be short enough that a crashed server does
		not lock a player out for long: a crash means the lock is never released, and the
		only way back in is for it to expire.
	]]
	HeartbeatSeconds = 30,
	LockTimeoutSeconds = 150,

	AutosaveSeconds = 60,

	--[[
		Load retries. A locked profile usually means the player's previous server has not
		finished releasing it, which resolves in seconds. Backoff is exponential and
		capped; total wait is roughly 1 + 2 + 4 + 8 + 16 = 31s before giving up.
	]]
	LoadAttempts = 5,
	LoadBackoffBaseSeconds = 1,
	LoadBackoffMaxSeconds = 16,

	SaveAttempts = 3,
	SaveBackoffBaseSeconds = 1,

	--[[
		Receipt history is bounded. docs/02 forbids saving unbounded history, and an
		unbounded map is also the most likely way a profile eventually exceeds the
		DataStore value size limit and stops saving entirely.
	]]
	MaxReceiptHistory = 50,

	-- Guard rails for repair. A field outside these is treated as corrupt, not clamped
	-- silently, so tampering is visible in the logs.
	MaxUpgradeLevel = 10000,
	MaxDiscoveryCount = 1e9,
})
