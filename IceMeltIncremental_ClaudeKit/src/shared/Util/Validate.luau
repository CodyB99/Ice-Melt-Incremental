--!strict

--[[
	Validate

	Primitives for checking anything that crossed the network. CLAUDE.md requires type,
	rate, state, and plausibility validation on every remote; this module covers type and
	plausibility, and the per-player rate limiter lives here too.

	Rules these encode, learned from how remote exploits actually work:
	  * `type(v) == "number"` is not enough. NaN and infinity are numbers, and NaN defeats
	    every comparison, so a naive `v > 0` check passes.
	  * Array payloads need a length cap checked before iterating, not during.
	  * Strings need a byte cap; a client can send megabytes.
]]

local Validate = {}

--[[
	True only for a real, finite number. Rejects NaN and both infinities.
]]
function Validate.isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	-- value ~= value is the NaN test; NaN fails every other comparison.
	return value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.isFiniteInRange(value: any, min: number, max: number): boolean
	if not Validate.isFiniteNumber(value) then
		return false
	end
	return value >= min and value <= max
end

--[[
	Whole number within range. Used for levels, indices, and sequence numbers, where a
	fractional value is always either a bug or an attack.
]]
function Validate.isIntegerInRange(value: any, min: number, max: number): boolean
	if not Validate.isFiniteInRange(value, min, max) then
		return false
	end
	return math.floor(value :: number) == value
end

function Validate.isNonEmptyString(value: any, maxBytes: number?): boolean
	if type(value) ~= "string" then
		return false
	end
	local length = #value
	return length > 0 and length <= (maxBytes or 128)
end

--[[
	A dense array of finite numbers, length-capped before any per-element work.
]]
function Validate.isNumberArray(value: any, maxLength: number): boolean
	if type(value) ~= "table" then
		return false
	end

	local count = #value
	if count == 0 or count > maxLength then
		return false
	end

	for index = 1, count do
		if not Validate.isFiniteNumber(value[index]) then
			return false
		end
	end

	-- Reject a table carrying extra non-array keys alongside the sequence.
	local total = 0
	for _ in value do
		total += 1
	end
	return total == count
end

function Validate.isKeyOf(value: any, map: { [string]: any }): boolean
	if type(value) ~= "string" then
		return false
	end
	return map[value] ~= nil
end

--[[
	Clamps into range and scrubs NaN. Use at the boundary where a computed stat is applied,
	so a bad multiplier degrades to a sane value instead of poisoning saved data.
]]
function Validate.clampFinite(value: number, min: number, max: number): number
	if not Validate.isFiniteNumber(value) then
		return min
	end
	return math.clamp(value, min, max)
end

-- === Rate limiting =========================================================

export type TokenBucket = {
	capacity: number,
	tokens: number,
	refillPerSecond: number,
	lastRefill: number,
}

--[[
	Token bucket, the shape the melt loop needs: a burst is fine, a sustained flood is not.
	`now` is passed in rather than read from os.clock() so this stays testable.
]]
function Validate.newTokenBucket(
	capacity: number,
	refillPerSecond: number,
	now: number
): TokenBucket
	return {
		capacity = capacity,
		tokens = capacity,
		refillPerSecond = refillPerSecond,
		lastRefill = now,
	}
end

--[[
	Consumes one token. Returns true when the request may proceed.
]]
function Validate.consumeToken(bucket: TokenBucket, now: number): boolean
	local elapsed = math.max(0, now - bucket.lastRefill)
	bucket.lastRefill = now
	bucket.tokens = math.min(bucket.capacity, bucket.tokens + elapsed * bucket.refillPerSecond)

	if bucket.tokens < 1 then
		return false
	end

	bucket.tokens -= 1
	return true
end

return table.freeze(Validate)
