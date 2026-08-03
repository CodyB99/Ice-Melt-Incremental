--!strict

--[[
	EffectSettings

	Where client effects ask whether the player wants reduced motion.

	Deliberately in Runtime rather than Controllers, so `ControllerRuntime.registerFolder` does
	not try to start it as a controller.

	The source is the player's own accessibility preference, read from Roblox, not a setting
	this project invented. That is the honest split for Phase 07: the profile has a `Settings`
	table and docs/06 lists a reduced-motion toggle, but the toggle UI belongs to Phase 08.
	Implementing the *behaviour* now from a real source, and deferring only the switch, means a
	player who has already asked their device for reduced motion gets it today rather than
	after the settings screen ships.

	What reduced motion means here, and the principle behind it: it removes MOTION, not
	FEEDBACK. Anything that carries information stays.

	    kept    -- the steam burst, at zero speed and a shorter life; it marks which cell broke
	    kept    -- crit colour and particle count; they say what happened
	    kept    -- the Heat popup, drawn static
	    kept    -- the chain wave shown at its final radius, fading; the extent is information,
	               the sweep is not
	    kept    -- all audio, unchanged
	    removed -- the anticipation pulse, which is pure motion
	    removed -- camera shake, unconditionally

	Server-driven cell geometry is never touched. The shrink applied as a cell weakens is one
	shared world state that replicates to everyone, and a client must not override server
	geometry to satisfy a local preference.
]]

local GuiService = game:GetService("GuiService")

local EffectSettings = {}

local reduced = false
local overridden: boolean? = nil

--[[
	Reads the platform preference defensively.

	The property cast is load-bearing: indexing a property that is not in the API dump is a
	type error under `luau-lsp analyze`, not merely a runtime one. The second pcall is separate
	because `GetPropertyChangedSignal` errors at runtime on an unknown property name, so a
	client on an older build must not take the whole controller down with it.
]]
local function readPlatform(): boolean
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

reduced = readPlatform()

pcall(function()
	GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		reduced = readPlatform()
	end)
end)

--[[
	True when effects should drop motion. An explicit override wins, which is what lets a
	dev command exercise both paths without changing a device setting.
]]
function EffectSettings.reducedMotion(): boolean
	if overridden ~= nil then
		return overridden
	end
	return reduced
end

--[[
	Development and testing only. `nil` returns to the platform preference.
]]
function EffectSettings.setOverride(value: boolean?)
	overridden = value
end

function EffectSettings.describe(): string
	return string.format(
		"reducedMotion=%s (platform=%s, override=%s)",
		tostring(EffectSettings.reducedMotion()),
		tostring(reduced),
		tostring(overridden)
	)
end

return EffectSettings
