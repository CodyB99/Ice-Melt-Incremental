--!strict

--[[
	NumberFormatter

	One place that turns numbers into player-facing text. CLAUDE.md caps ordinary MVP
	values near 1e15 precisely so a BigNum system is never needed; this handles everything
	below that and degrades to scientific notation above it rather than printing nonsense.

	All functions are total: NaN and infinity produce a visible placeholder instead of
	"nan" or "inf" leaking into the HUD.
]]

local NumberFormatter = {}

local SUFFIXES = table.freeze({
	{ Value = 1e15, Suffix = "Qa" },
	{ Value = 1e12, Suffix = "T" },
	{ Value = 1e9, Suffix = "B" },
	{ Value = 1e6, Suffix = "M" },
	{ Value = 1e3, Suffix = "K" },
})

local function isBadNumber(value: number): boolean
	-- value ~= value catches NaN; the comparison catches both infinities.
	return value ~= value or value == math.huge or value == -math.huge
end

--[[
	Groups the integer part with commas: 1234567 -> "1,234,567".
	Intended for exact readouts such as costs, not for large HUD counters.
]]
function NumberFormatter.comma(value: number): string
	if isBadNumber(value) then
		return "--"
	end

	local negative = value < 0
	local whole = math.floor(math.abs(value))
	local text = string.format("%.0f", whole)

	while true do
		local replaced, count = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if count == 0 then
			break
		end
	end

	return if negative then "-" .. text else text
end

--[[
	Compact form for HUD counters: 1234 -> "1.23K", 45600000 -> "45.6M".
	Values under 1000 are shown whole, because "0.99K" reads worse than "990".
]]
function NumberFormatter.abbreviate(value: number, decimals: number?): string
	if isBadNumber(value) then
		return "--"
	end

	local places = decimals or 2
	local negative = value < 0
	local magnitude = math.abs(value)

	if magnitude < 1000 then
		local whole = math.floor(magnitude + 0.5)
		return if negative then "-" .. tostring(whole) else tostring(whole)
	end

	for _, entry in SUFFIXES do
		if magnitude >= entry.Value then
			local scaled = magnitude / entry.Value

			-- Above the largest suffix, fall back to scientific notation rather than
			-- printing an ever-growing number of digits.
			if entry.Value == 1e15 and scaled >= 1000 then
				local text = string.format("%.2e", magnitude)
				return if negative then "-" .. text else text
			end

			-- Trim trailing zeros so it reads "1.5M", not "1.50M".
			local text = string.format("%." .. tostring(places) .. "f", scaled)
			text = string.gsub(text, "%.?0+$", "")
			return (if negative then "-" else "") .. text .. entry.Suffix
		end
	end

	return tostring(value)
end

--[[
	0.035 -> "3.5%". Takes a fraction, not an already-multiplied percentage.
]]
function NumberFormatter.percent(fraction: number, decimals: number?): string
	if isBadNumber(fraction) then
		return "--"
	end

	local places = decimals or 1
	local text = string.format("%." .. tostring(places) .. "f", fraction * 100)
	text = string.gsub(text, "%.?0+$", "")
	return text .. "%"
end

--[[
	Multipliers read better without a redundant decimal: 2 -> "x2", 1.25 -> "x1.25".
]]
function NumberFormatter.multiplier(value: number, decimals: number?): string
	if isBadNumber(value) then
		return "--"
	end

	local text = string.format("%." .. tostring(decimals or 2) .. "f", value)
	text = string.gsub(text, "%.?0+$", "")
	return "x" .. text
end

--[[
	Seconds to a compact duration: 90 -> "1m 30s", 3700 -> "1h 1m".
	Used for reward cooldowns and boost timers.
]]
function NumberFormatter.duration(seconds: number): string
	if isBadNumber(seconds) or seconds < 0 then
		return "--"
	end

	local total = math.floor(seconds)
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	local secs = total % 60

	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	end
	if minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

return table.freeze(NumberFormatter)
